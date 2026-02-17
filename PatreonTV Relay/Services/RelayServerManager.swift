//
//  RelayServerManager.swift
//  PatreonTV Relay
//
//  Manages the HTTP relay server for authentication
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import Foundation
import Network

/// Manages the relay HTTP server
@MainActor
class RelayServerManager: ObservableObject {
    static let shared = RelayServerManager()

    @Published var isRunning = false
    @Published var port: UInt16 = 8080
    @Published var localIP: String = "127.0.0.1"
    @Published var allLocalIPs: [String] = []
    @Published var pairingSessions: [String: PairingSessionData] = [:]
    @Published var connectedClients: [String] = []
    @Published var logs: [LogEntry] = []

    private var listener: NWListener?
    private var connections: [NWConnection] = []
    private var bonjourService: NWListener?

    /// Bonjour service type for relay server discovery
    static let bonjourServiceType = "_patreontv._tcp"

    struct PairingSessionData {
        let code: String
        var status: String
        var sessionToken: String?
        var userName: String?
        let createdAt: Date
        var expiresAt: Date

        var isExpired: Bool {
            Date() > expiresAt
        }
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let type: LogType

        enum LogType {
            case info, success, warning, error
        }
    }

    private init() {
        // Get all local IPs and pick the primary one
        allLocalIPs = getAllLocalIPAddresses()
        localIP = allLocalIPs.first ?? "127.0.0.1"
    }

    // MARK: - Server Control

    func startServer() async {
        guard !isRunning else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)

            listener?.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                        self?.log("Server started on port \(self?.port ?? 8080)", type: .success)
                    case .failed(let error):
                        self?.log("Server failed: \(error)", type: .error)
                        self?.isRunning = false
                    case .cancelled:
                        self?.isRunning = false
                        self?.log("Server stopped", type: .info)
                    default:
                        break
                    }
                }
            }

            listener?.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }

            listener?.start(queue: .main)
            log("Starting server on \(localIP):\(port)...", type: .info)

            // Advertise via Bonjour so Apple TV can discover us
            publishBonjourService()

        } catch {
            log("Failed to start server: \(error)", type: .error)
        }
    }

    /// Publish Bonjour service so Apple TV can discover the relay server
    private func publishBonjourService() {
        do {
            let parameters = NWParameters()
            parameters.includePeerToPeer = true

            let bonjourListener = try NWListener(using: parameters)
            bonjourListener.service = NWListener.Service(
                name: "PatreonTV Relay",
                type: RelayServerManager.bonjourServiceType,
                domain: nil,
                txtRecord: NWTXTRecord(["host": localIP, "port": String(port)])
            )
            bonjourListener.serviceRegistrationUpdateHandler = { [weak self] change in
                Task { @MainActor in
                    switch change {
                    case .add(let endpoint):
                        self?.log("Bonjour service published: \(endpoint)", type: .success)
                    case .remove:
                        self?.log("Bonjour service removed", type: .info)
                    @unknown default:
                        break
                    }
                }
            }
            bonjourListener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    if case .failed(let error) = state {
                        self?.log("Bonjour publish failed: \(error)", type: .warning)
                    }
                }
            }
            bonjourListener.newConnectionHandler = { connection in
                // Not used for discovery, just required by NWListener
                connection.cancel()
            }
            bonjourListener.start(queue: .main)
            self.bonjourService = bonjourListener
        } catch {
            log("Failed to publish Bonjour service: \(error)", type: .warning)
        }
    }

    func stopServer() {
        bonjourService?.cancel()
        bonjourService = nil
        listener?.cancel()
        listener = nil
        connections.forEach { $0.cancel() }
        connections.removeAll()
        isRunning = false
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.log("Client connected", type: .info)
                case .failed(let error):
                    self?.log("Connection failed: \(error)", type: .warning)
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        connections.append(connection)

        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                Task { @MainActor in
                    self?.handleRequest(data: data, connection: connection)
                }
            }

            if let error = error {
                print("Receive error: \(error)")
                return
            }

            if !isComplete {
                Task { @MainActor in
                    self?.receiveData(on: connection)
                }
            }
        }
    }

    // MARK: - HTTP Request Handling

    private func handleRequest(data: Data, connection: NWConnection) {
        guard let requestString = String(data: data, encoding: .utf8) else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid request")
            return
        }

        let lines = requestString.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid request")
            return
        }

        let parts = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else {
            sendResponse(connection: connection, status: "400 Bad Request", body: "Invalid request")
            return
        }

        let method = parts[0]
        let path = parts[1]

        log("\(method) \(path)", type: .info)

        // Route the request
        switch (method, path) {
        case ("GET", let p) where p.hasPrefix("/pair/"):
            handlePairPage(path: p, connection: connection)

        case ("POST", "/api/pairing/register"):
            handlePairingRegister(data: data, connection: connection)

        case ("GET", let p) where p.hasPrefix("/api/pairing/status/"):
            handlePairingStatus(path: p, connection: connection)

        case ("POST", let p) where p.hasPrefix("/api/pairing/complete/"):
            handlePairingComplete(path: p, data: data, connection: connection)

        case ("GET", "/"):
            sendResponse(connection: connection, status: "200 OK", body: "PatreonTV Relay Server Running")

        case ("GET", "/health"):
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\":\"ok\"}")

        default:
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    // MARK: - Pairing Endpoints

    private func handlePairPage(path: String, connection: NWConnection) {
        let code = String(path.dropFirst("/pair/".count))

        guard let session = pairingSessions[code], !session.isExpired else {
            sendResponse(connection: connection, status: "404 Not Found", body: "Pairing code expired or invalid")
            return
        }

        // Update status to scanning
        pairingSessions[code]?.status = "scanning"

        // Serve the login page HTML
        let html = generateLoginPageHTML(code: code)
        sendResponse(connection: connection, status: "200 OK", contentType: "text/html", body: html)
    }

    private func handlePairingRegister(data: Data, connection: NWConnection) {
        // Parse JSON body
        guard let bodyStart = String(data: data, encoding: .utf8)?.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid request\"}")
            return
        }

        let bodyString = String(data: data, encoding: .utf8)!
        let jsonString = String(bodyString[bodyStart.upperBound...])

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: String].self, from: jsonData),
              let code = json["code"] else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Missing code\"}")
            return
        }

        // Create pairing session
        let session = PairingSessionData(
            code: code,
            status: "pending",
            sessionToken: nil,
            userName: nil,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(300) // 5 minutes
        )

        pairingSessions[code] = session
        log("Pairing session registered: \(code)", type: .success)

        sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\":\"registered\"}")
    }

    private func handlePairingStatus(path: String, connection: NWConnection) {
        let code = String(path.dropFirst("/api/pairing/status/".count))

        guard let session = pairingSessions[code] else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "application/json", body: "{\"error\":\"Session not found\"}")
            return
        }

        if session.isExpired {
            pairingSessions[code]?.status = "expired"
        }

        var response: [String: Any] = ["status": pairingSessions[code]?.status ?? "unknown"]

        if let token = session.sessionToken {
            response["session_token"] = token
        }
        if let userName = session.userName {
            response["user_name"] = userName
        }

        if let jsonData = try? JSONSerialization.data(withJSONObject: response),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: jsonString)
        }
    }

    private func handlePairingComplete(path: String, data: Data, connection: NWConnection) {
        let code = String(path.dropFirst("/api/pairing/complete/".count))

        guard pairingSessions[code] != nil else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "application/json", body: "{\"error\":\"Session not found\"}")
            return
        }

        // Parse the session token from the request body
        guard let bodyStart = String(data: data, encoding: .utf8)?.range(of: "\r\n\r\n") else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Invalid request\"}")
            return
        }

        let bodyString = String(data: data, encoding: .utf8)!
        let jsonString = String(bodyString[bodyStart.upperBound...])

        guard let jsonData = jsonString.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: String].self, from: jsonData),
              let sessionToken = json["session_token"] else {
            sendResponse(connection: connection, status: "400 Bad Request", contentType: "application/json", body: "{\"error\":\"Missing session_token\"}")
            return
        }

        // Update the pairing session
        pairingSessions[code]?.sessionToken = sessionToken
        pairingSessions[code]?.userName = json["user_name"]
        pairingSessions[code]?.status = "completed"

        log("Pairing completed for code: \(code)", type: .success)

        sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\":\"completed\"}")
    }

    // MARK: - HTTP Response

    private func sendResponse(connection: NWConnection, status: String, contentType: String = "text/plain", body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.utf8.count)\r
        Access-Control-Allow-Origin: *\r
        Connection: close\r
        \r
        \(body)
        """

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Login Page HTML

    private func generateLoginPageHTML(code: String) -> String {
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>PatreonTV Login</title>
            <style>
                * { box-sizing: border-box; margin: 0; padding: 0; }
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
                    min-height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    color: white;
                }
                .container {
                    text-align: center;
                    padding: 40px;
                    max-width: 500px;
                }
                .logo {
                    font-size: 48px;
                    margin-bottom: 20px;
                }
                h1 {
                    font-size: 28px;
                    margin-bottom: 10px;
                }
                .subtitle {
                    color: #888;
                    margin-bottom: 40px;
                }
                .step {
                    background: rgba(255,255,255,0.1);
                    border-radius: 12px;
                    padding: 20px;
                    margin-bottom: 20px;
                    text-align: left;
                }
                .step-number {
                    background: #f96854;
                    color: white;
                    width: 30px;
                    height: 30px;
                    border-radius: 50%;
                    display: inline-flex;
                    align-items: center;
                    justify-content: center;
                    margin-right: 12px;
                    font-weight: bold;
                }
                .patreon-btn {
                    display: inline-block;
                    background: #f96854;
                    color: white;
                    padding: 16px 32px;
                    border-radius: 8px;
                    text-decoration: none;
                    font-weight: 600;
                    font-size: 18px;
                    margin: 20px 0;
                    transition: transform 0.2s;
                }
                .patreon-btn:hover {
                    transform: scale(1.05);
                }
                .input-group {
                    margin: 20px 0;
                }
                input {
                    width: 100%;
                    padding: 12px 16px;
                    border: 2px solid rgba(255,255,255,0.2);
                    border-radius: 8px;
                    background: rgba(255,255,255,0.1);
                    color: white;
                    font-size: 16px;
                }
                input:focus {
                    outline: none;
                    border-color: #f96854;
                }
                .submit-btn {
                    background: #4CAF50;
                    color: white;
                    border: none;
                    padding: 16px 32px;
                    border-radius: 8px;
                    font-size: 18px;
                    font-weight: 600;
                    cursor: pointer;
                    width: 100%;
                }
                .submit-btn:hover {
                    background: #45a049;
                }
                .instructions {
                    background: rgba(255,255,255,0.05);
                    border-radius: 8px;
                    padding: 16px;
                    margin-top: 20px;
                    font-size: 14px;
                    color: #aaa;
                    text-align: left;
                }
                .instructions ol {
                    padding-left: 20px;
                }
                .instructions li {
                    margin-bottom: 8px;
                }
                .success {
                    background: #4CAF50;
                    padding: 20px;
                    border-radius: 12px;
                    margin-top: 20px;
                }
                .hidden { display: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="logo">📺</div>
                <h1>PatreonTV Login</h1>
                <p class="subtitle">Connect your Patreon account to your Apple TV</p>

                <div class="step">
                    <span class="step-number">1</span>
                    <span>Open Patreon in a new tab and log in</span>
                </div>

                <a href="https://www.patreon.com/login" target="_blank" class="patreon-btn">
                    Open Patreon Login →
                </a>

                <div class="step">
                    <span class="step-number">2</span>
                    <span>After logging in, copy your session_id cookie</span>
                </div>

                <div class="instructions">
                    <strong>How to get your session_id:</strong>
                    <ol>
                        <li>After logging in to Patreon, open Developer Tools (F12 or Cmd+Option+I)</li>
                        <li>Go to Application → Cookies → www.patreon.com</li>
                        <li>Find "session_id" and copy its value</li>
                        <li>Paste it below</li>
                    </ol>
                </div>

                <div class="step">
                    <span class="step-number">3</span>
                    <span>Paste your session_id below</span>
                </div>

                <form id="loginForm">
                    <div class="input-group">
                        <input type="text" id="sessionToken" placeholder="Paste your session_id here" required>
                    </div>
                    <button type="submit" class="submit-btn">Connect to Apple TV</button>
                </form>

                <div id="success" class="success hidden">
                    <h2>✅ Success!</h2>
                    <p>Your Apple TV should now be connected. You can close this page.</p>
                </div>
            </div>

            <script>
                document.getElementById('loginForm').addEventListener('submit', async (e) => {
                    e.preventDefault();
                    const sessionToken = document.getElementById('sessionToken').value.trim();

                    if (!sessionToken) {
                        alert('Please enter your session_id');
                        return;
                    }

                    try {
                        const response = await fetch('/api/pairing/complete/\(code)', {
                            method: 'POST',
                            headers: { 'Content-Type': 'application/json' },
                            body: JSON.stringify({ session_token: sessionToken })
                        });

                        if (response.ok) {
                            document.getElementById('loginForm').classList.add('hidden');
                            document.getElementById('success').classList.remove('hidden');
                        } else {
                            alert('Failed to connect. Please try again.');
                        }
                    } catch (error) {
                        alert('Error: ' + error.message);
                    }
                });
            </script>
        </body>
        </html>
        """
    }

    // MARK: - Utilities

    private func log(_ message: String, type: LogEntry.LogType) {
        let entry = LogEntry(timestamp: Date(), message: message, type: type)
        logs.insert(entry, at: 0)

        // Keep only last 100 entries
        if logs.count > 100 {
            logs = Array(logs.prefix(100))
        }

        print("[RelayServer] \(message)")
    }

    /// Returns all local IPv4 addresses on active network interfaces (en0, en1, etc.)
    private func getAllLocalIPAddresses() -> [String] {
        var addresses: [String] = []

        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else {
            return []
        }

        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let addrFamily = interface.ifa_addr.pointee.sa_family

            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: interface.ifa_name)

                // Include en0 (usually Ethernet) and en1 (usually WiFi)
                if name.hasPrefix("en") {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    getnameinfo(
                        interface.ifa_addr,
                        socklen_t(interface.ifa_addr.pointee.sa_len),
                        &hostname,
                        socklen_t(hostname.count),
                        nil, 0,
                        NI_NUMERICHOST
                    )
                    let ip = String(cString: hostname)
                    if !ip.isEmpty && ip != "0.0.0.0" {
                        addresses.append(ip)
                    }
                }
            }
        }

        return addresses
    }

    // MARK: - Cleanup

    func cleanupExpiredSessions() {
        let expired = pairingSessions.filter { $0.value.isExpired }
        for (code, _) in expired {
            pairingSessions.removeValue(forKey: code)
            log("Cleaned up expired session: \(code)", type: .info)
        }
    }
}
