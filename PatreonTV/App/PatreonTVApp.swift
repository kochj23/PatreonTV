//
//  PatreonTVApp.swift
//  PatreonTV
//
//  Main entry point for the PatreonTV Apple TV app
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI
import Network

@main
struct PatreonTVApp: App {
    @StateObject private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
        }
    }
}

// MARK: - Auth Manager

/// Manages authentication state across the app
class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published var isAuthenticated = false
    @Published var isPairing = false
    @Published var currentUser: PatreonUser?
    @Published var pairingSession: PairingSession?
    @Published var errorMessage: String?

    private let api = PatreonAPI.shared
    private var pollingTimer: Timer?

    // Relay server configuration - discovered via Bonjour
    @Published var relayServerHost: String = ""
    @Published var relayServerPort: Int = 8080
    @Published var isDiscoveringRelay: Bool = true
    @Published var relayDiscovered: Bool = false

    private var browser: NWBrowser?

    private init() {
        // Discover relay server via Bonjour, then restore session
        discoverRelayServer()
        restoreSession()
    }

    deinit {
        browser?.cancel()
    }

    // MARK: - Bonjour Discovery

    /// Discover the PatreonTV Relay server on the local network via Bonjour
    private func discoverRelayServer() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: "_patreontv._tcp", domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true

        let browser = NWBrowser(for: descriptor, using: parameters)

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                guard let self = self else { return }

                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        print("[AuthManager] Found Bonjour service: \(name)")

                        // Resolve the service to get TXT record with host/port
                        let metadata = result.metadata
                        if case .bonjour(let txtRecord) = metadata {
                            if let host = txtRecord["host"],
                               let portStr = txtRecord["port"],
                               let port = Int(portStr) {
                                self.relayServerHost = host
                                self.relayServerPort = port
                                self.relayDiscovered = true
                                self.isDiscoveringRelay = false
                                print("[AuthManager] Relay server discovered at \(host):\(port)")
                                return
                            }
                        }

                        // Fallback: resolve the endpoint directly
                        self.resolveEndpoint(result.endpoint)
                    }
                }
            }
        }

        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    print("[AuthManager] Bonjour browser ready, searching for relay...")
                case .failed(let error):
                    print("[AuthManager] Bonjour browser failed: \(error)")
                    self?.isDiscoveringRelay = false
                default:
                    break
                }
            }
        }

        browser.start(queue: .main)
        self.browser = browser

        // Timeout after 10 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !self.relayDiscovered else { return }
            self.isDiscoveringRelay = false
            print("[AuthManager] Relay server discovery timed out")
        }
    }

    /// Resolve a Bonjour endpoint to get host and port
    private func resolveEndpoint(_ endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                if case .ready = state {
                    if let innerEndpoint = connection.currentPath?.remoteEndpoint,
                       case .hostPort(let host, let port) = innerEndpoint {
                        let hostString = "\(host)"
                        // Strip IPv6 prefix if present
                        let cleanHost = hostString.replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
                        self?.relayServerHost = cleanHost
                        self?.relayServerPort = Int(port.rawValue)
                        self?.relayDiscovered = true
                        self?.isDiscoveringRelay = false
                        print("[AuthManager] Relay resolved to \(cleanHost):\(port)")
                    }
                    connection.cancel()
                }
            }
        }
        connection.start(queue: .main)
    }

    // MARK: - Session Management

    /// Restore session from Keychain
    private func restoreSession() {
        if let sessionID = KeychainService.shared.getSessionID() {
            api.sessionID = sessionID

            // Validate the session
            Task { @MainActor in
                do {
                    let user = try await api.validateSession()
                    self.currentUser = user
                    self.isAuthenticated = true
                    print("[AuthManager] Session restored for user: \(user.fullName)")
                } catch {
                    print("[AuthManager] Session invalid, clearing: \(error)")
                    KeychainService.shared.clearSessionID()
                    api.sessionID = nil
                }
            }
        }
    }

    /// Save session to Keychain
    private func saveSession(_ sessionID: String) {
        KeychainService.shared.saveSessionID(sessionID)
        api.sessionID = sessionID
    }

    /// Clear session and log out
    func logout() {
        KeychainService.shared.clearSessionID()
        api.logout()
        isAuthenticated = false
        currentUser = nil
        pairingSession = nil
    }

    // MARK: - Pairing Flow

    /// Start the pairing process
    func startPairing() {
        guard relayDiscovered else {
            errorMessage = "Relay server not found. Make sure PatreonTV Relay is running on your Mac and both devices are on the same network."
            return
        }

        let code = PairingSession.generateCode()
        pairingSession = PairingSession(code: code)
        isPairing = true
        errorMessage = nil

        print("[AuthManager] Starting pairing with code: \(code) -> relay at \(relayServerHost):\(relayServerPort)")

        // Register the pairing session with the relay server
        Task { @MainActor in
            do {
                try await registerPairingSession(code: code)
                startPollingForAuth()
            } catch {
                self.errorMessage = "Failed to connect to relay server at \(relayServerHost):\(relayServerPort) — \(error.localizedDescription)"
                print("[AuthManager] Failed to register pairing: \(error)")
            }
        }
    }

    /// Register pairing session with relay server
    private func registerPairingSession(code: String) async throws {
        let url = URL(string: "http://\(relayServerHost):\(relayServerPort)/api/pairing/register")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["code": code]
        request.httpBody = try JSONEncoder().encode(body)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw AuthError.relayServerError
        }

        print("[AuthManager] Pairing session registered with relay")
    }

    /// Poll the relay server for authentication completion
    private func startPollingForAuth() {
        pollingTimer?.invalidate()
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkPairingStatus()
            }
        }
    }

    /// Check if pairing has completed
    private func checkPairingStatus() async {
        guard let session = pairingSession, !session.isExpired else {
            stopPolling()
            if pairingSession?.isExpired == true {
                errorMessage = "Pairing code expired. Please try again."
                pairingSession?.status = .expired
            }
            return
        }

        do {
            let url = URL(string: "http://\(relayServerHost):\(relayServerPort)/api/pairing/status/\(session.code)")!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return
            }

            struct StatusResponse: Codable {
                let status: String
                let sessionToken: String?
                let userName: String?

                enum CodingKeys: String, CodingKey {
                    case status
                    case sessionToken = "session_token"
                    case userName = "user_name"
                }
            }

            let status = try JSONDecoder().decode(StatusResponse.self, from: data)

            switch status.status {
            case "completed":
                if let token = status.sessionToken {
                    await handleAuthenticationSuccess(sessionToken: token)
                }
            case "authenticating":
                pairingSession?.status = .authenticating
            case "scanning":
                pairingSession?.status = .scanning
            case "failed":
                pairingSession?.status = .failed
                errorMessage = "Authentication failed. Please try again."
                stopPolling()
            default:
                break
            }
        } catch {
            print("[AuthManager] Error checking pairing status: \(error)")
        }
    }

    /// Handle successful authentication
    private func handleAuthenticationSuccess(sessionToken: String) async {
        stopPolling()
        saveSession(sessionToken)

        do {
            let user = try await api.validateSession()
            currentUser = user
            isAuthenticated = true
            isPairing = false
            pairingSession?.status = .completed
            print("[AuthManager] Authentication successful for: \(user.fullName)")
        } catch {
            errorMessage = "Failed to validate session: \(error.localizedDescription)"
            pairingSession?.status = .failed
        }
    }

    /// Stop polling for auth status
    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    /// Cancel pairing
    func cancelPairing() {
        stopPolling()
        isPairing = false
        pairingSession = nil
        errorMessage = nil
    }

    /// Generate QR code URL for pairing
    var pairingURL: String? {
        guard let code = pairingSession?.code else { return nil }
        return "http://\(relayServerHost):\(relayServerPort)/pair/\(code)"
    }
}

// MARK: - Keychain Service

/// Simple Keychain wrapper for storing session ID
class KeychainService {
    static let shared = KeychainService()

    private let sessionKey = "com.jordankoch.patreontv.session"

    private init() {}

    func saveSessionID(_ sessionID: String) {
        let data = sessionID.data(using: .utf8)!

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
            kSecValueData as String: data
        ]

        // Delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            print("[Keychain] Error saving session: \(status)")
        }
    }

    func getSessionID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }

        return nil
    }

    func clearSessionID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: sessionKey
        ]

        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case relayServerError
    case pairingExpired
    case authenticationFailed

    var errorDescription: String? {
        switch self {
        case .relayServerError:
            return "Could not connect to the relay server. Make sure it's running on your Mac."
        case .pairingExpired:
            return "Pairing code has expired. Please try again."
        case .authenticationFailed:
            return "Authentication failed. Please try again."
        }
    }
}
