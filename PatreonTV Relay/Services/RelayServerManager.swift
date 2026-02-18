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
    @Published var pendingLoginCode: String?
    @Published var showLoginSheet = false

    // Media proxy stats
    @Published var activeStreamCount: Int = 0
    @Published var totalBytesProxied: UInt64 = 0

    // Persistent Patreon session — stored on the relay, used for all API calls
    @Published var patreonSessionID: String? {
        didSet {
            if let sid = patreonSessionID {
                UserDefaults.standard.set(sid, forKey: "patreon_session_id")
                log("Patreon session stored on relay", type: .success)
            } else {
                UserDefaults.standard.removeObject(forKey: "patreon_session_id")
            }
        }
    }
    @Published var patreonSessionValid: Bool = false
    @Published var patreonUserName: String?

    private let mediaProxy = MediaProxyService.shared
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

        // Restore persisted Patreon session
        if let storedSession = UserDefaults.standard.string(forKey: "patreon_session_id"), !storedSession.isEmpty {
            patreonSessionID = storedSession
            print("[RelayServer] Restored Patreon session from disk: \(storedSession.prefix(20))...")
            // Validate the stored session
            Task { await validatePatreonSession() }
        }
    }

    /// Validate the stored Patreon session by calling the Patreon API
    func validatePatreonSession() async {
        guard let sessionID = patreonSessionID else {
            patreonSessionValid = false
            patreonUserName = nil
            return
        }

        let urlString = "https://www.patreon.com/api/current_user?fields[user]=full_name"
        guard let url = URL(string: urlString) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                patreonSessionValid = true

                // Extract user name
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let userData = json["data"] as? [String: Any],
                   let attrs = userData["attributes"] as? [String: Any],
                   let name = attrs["full_name"] as? String {
                    patreonUserName = name
                    log("Patreon session valid — logged in as \(name)", type: .success)
                } else {
                    log("Patreon session valid", type: .success)
                }
            } else {
                patreonSessionValid = false
                patreonUserName = nil
                log("Patreon session expired or invalid", type: .warning)
            }
        } catch {
            patreonSessionValid = false
            patreonUserName = nil
            log("Failed to validate Patreon session: \(error.localizedDescription)", type: .error)
        }
    }

    /// Clear the stored Patreon session (for re-login)
    func clearPatreonSession() {
        patreonSessionID = nil
        patreonSessionValid = false
        patreonUserName = nil
        log("Patreon session cleared", type: .info)
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

    /// Tracks buffered data per connection while waiting for a complete HTTP request
    private var connectionBuffers: [ObjectIdentifier: Data] = [:]

    private func handleConnection(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                switch state {
                case .ready:
                    self?.log("Client connected", type: .info)
                case .failed(let error):
                    self?.log("Connection failed: \(error)", type: .warning)
                    self?.connectionBuffers.removeValue(forKey: ObjectIdentifier(connection))
                case .cancelled:
                    self?.connectionBuffers.removeValue(forKey: ObjectIdentifier(connection))
                default:
                    break
                }
            }
        }

        connection.start(queue: .main)
        connections.append(connection)
        connectionBuffers[ObjectIdentifier(connection)] = Data()

        receiveData(on: connection)
    }

    private func receiveData(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            Task { @MainActor in
                guard let self = self else { return }
                let connID = ObjectIdentifier(connection)

                if let data = data, !data.isEmpty {
                    self.connectionBuffers[connID, default: Data()].append(data)
                }

                // Check if we have a complete HTTP request
                if let buffered = self.connectionBuffers[connID],
                   let requestString = String(data: buffered, encoding: .utf8) {

                    // For GET requests, we just need the headers (ending with \r\n\r\n)
                    // For POST requests, we need headers + Content-Length bytes of body
                    if requestString.contains("\r\n\r\n") {
                        let headerEnd = requestString.range(of: "\r\n\r\n")!
                        let headerPart = String(requestString[..<headerEnd.lowerBound])

                        // Check if it's a POST with Content-Length
                        let method = requestString.components(separatedBy: " ").first ?? ""
                        if method == "POST" {
                            // Extract Content-Length
                            let contentLength = self.extractContentLength(from: headerPart)
                            let bodyStart = requestString[headerEnd.upperBound...]
                            let bodyBytes = bodyStart.utf8.count

                            if bodyBytes < contentLength {
                                // Need more data, keep reading
                                if !isComplete {
                                    self.receiveData(on: connection)
                                }
                                return
                            }
                        }

                        // We have a complete request, process it
                        self.connectionBuffers.removeValue(forKey: connID)
                        self.handleRequest(data: buffered, connection: connection)
                        return
                    }
                }

                if let error = error {
                    print("Receive error: \(error)")
                    self.connectionBuffers.removeValue(forKey: connID)
                    return
                }

                if !isComplete {
                    self.receiveData(on: connection)
                } else if let buffered = self.connectionBuffers[connID], !buffered.isEmpty {
                    // Connection complete but we have data - process what we have
                    self.connectionBuffers.removeValue(forKey: connID)
                    self.handleRequest(data: buffered, connection: connection)
                }
            }
        }
    }

    /// Parse all HTTP headers from raw request data into a dictionary
    private func parseRequestHeaders(from requestString: String) -> [String: String] {
        var headers: [String: String] = [:]
        let lines = requestString.components(separatedBy: "\r\n")
        // Skip request line (first line), parse until empty line
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces).lowercased()
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }
        return headers
    }

    /// Extract Content-Length header value from HTTP headers
    private func extractContentLength(from headers: String) -> Int {
        for line in headers.components(separatedBy: "\r\n") {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2,
               parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length",
               let length = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                return length
            }
        }
        return 0
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
            let sessionStatus = patreonSessionValid ? "valid" : (patreonSessionID != nil ? "expired" : "none")
            let userName = patreonUserName ?? ""
            sendResponse(connection: connection, status: "200 OK", contentType: "application/json",
                         body: "{\"status\":\"ok\",\"session\":\"\(sessionStatus)\",\"user\":\"\(userName)\"}")

        case ("GET", "/api/session/status"):
            handleSessionStatus(connection: connection)

        case ("POST", "/api/session/relogin"):
            handleReloginRequest(connection: connection)

        case ("GET", let p) where p.hasPrefix("/api/media/stream/"):
            let requestString = String(data: data, encoding: .utf8) ?? ""
            handleMediaStream(path: p, requestString: requestString, connection: connection)

        default:
            sendResponse(connection: connection, status: "404 Not Found", body: "Not Found")
        }
    }

    // MARK: - Pairing Endpoints

    private func handlePairPage(path: String, connection: NWConnection) {
        let code = String(path.dropFirst("/pair/".count))

        guard let session = pairingSessions[code], !session.isExpired else {
            sendResponse(connection: connection, status: "404 Not Found", contentType: "text/html", body: "<html><body style='font-family:system-ui;text-align:center;padding:60px;background:#1a1a2e;color:white'><h1>Pairing Code Expired</h1><p>Please start a new pairing session from your Apple TV.</p></body></html>")
            return
        }

        // Update status to scanning
        pairingSessions[code]?.status = "scanning"
        log("QR code scanned for pairing code: \(code)", type: .success)

        // Trigger the native login window on the Mac
        pendingLoginCode = code
        showLoginSheet = true

        // Respond to the browser
        let html = "<html><body style='font-family:system-ui;text-align:center;padding:60px;background:#1a1a2e;color:white'><h1>📺 PatreonTV</h1><p style='font-size:20px;margin-top:20px'>A login window has opened on your Mac.</p><p style='color:#888;margin-top:12px'>Log in to Patreon in the window that appeared on the Mac running PatreonTV Relay.</p><p style='color:#888;margin-top:8px'>Your session will be sent to Apple TV automatically.</p></body></html>"
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

        // Store session on the relay for media proxy use
        patreonSessionID = sessionToken
        Task { await validatePatreonSession() }

        log("Pairing completed for code: \(code)", type: .success)

        sendResponse(connection: connection, status: "200 OK", contentType: "application/json", body: "{\"status\":\"completed\"}")
    }

    // MARK: - HTTP Response

    private func sendResponse(connection: NWConnection, status: String, contentType: String = "text/plain", body: String) {
        var response = "HTTP/1.1 \(status)\r\n"
        response += "Content-Type: \(contentType)\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Connection: close\r\n"
        response += "\r\n"
        response += body

        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    /// Send a 302 redirect response. Used for YouTube/Vimeo HLS streams
    /// where AVPlayer should follow the URL directly.
    private func sendRedirect(connection: NWConnection, location: String) {
        var response = "HTTP/1.1 302 Found\r\n"
        response += "Location: \(location)\r\n"
        response += "Access-Control-Allow-Origin: *\r\n"
        response += "Connection: close\r\n"
        response += "Content-Length: 0\r\n"
        response += "\r\n"

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

    // MARK: - Pairing Completion (from native WebView)

    /// Complete a pairing session with a captured session token from the WebView login
    func completePairing(code: String, sessionToken: String) {
        guard pairingSessions[code] != nil else {
            log("Cannot complete pairing: session \(code) not found", type: .error)
            return
        }

        pairingSessions[code]?.sessionToken = sessionToken
        pairingSessions[code]?.status = "completed"
        pendingLoginCode = nil
        showLoginSheet = false

        // Store session on the relay for media proxy use
        patreonSessionID = sessionToken
        log("Patreon session stored on relay", type: .success)

        // Validate the session asynchronously
        Task { await validatePatreonSession() }

        log("Pairing completed for code: \(code) (via native login)", type: .success)
    }

    // MARK: - Session Management Endpoints

    private func handleSessionStatus(connection: NWConnection) {
        let status: String
        if patreonSessionValid {
            status = "valid"
        } else if patreonSessionID != nil {
            status = "expired"
        } else {
            status = "none"
        }

        let userName = patreonUserName ?? ""
        sendResponse(connection: connection, status: "200 OK", contentType: "application/json",
                     body: "{\"status\":\"\(status)\",\"user\":\"\(userName)\"}")
    }

    private func handleReloginRequest(connection: NWConnection) {
        // Open the login sheet for re-authentication
        // Use a dummy pairing code since this isn't part of Apple TV pairing
        let reloginCode = "relogin-\(UUID().uuidString.prefix(8))"
        let session = PairingSessionData(
            code: reloginCode,
            status: "authenticating",
            sessionToken: nil,
            userName: nil,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(600) // 10 minutes
        )
        pairingSessions[reloginCode] = session
        pendingLoginCode = reloginCode
        showLoginSheet = true

        log("Re-login requested — opening Patreon login window", type: .info)
        sendResponse(connection: connection, status: "200 OK", contentType: "application/json",
                     body: "{\"status\":\"login_window_opened\"}")
    }

    // MARK: - Media Streaming Proxy

    private func handleMediaStream(path: String, requestString: String, connection: NWConnection) {
        // Extract post ID and query params
        let pathAfterPrefix = String(path.dropFirst("/api/media/stream/".count))
        let postID = pathAfterPrefix.components(separatedBy: "?").first ?? pathAfterPrefix

        guard !postID.isEmpty else {
            sendResponse(connection: connection, status: "400 Bad Request",
                         contentType: "application/json", body: "{\"error\":\"Missing post ID\"}")
            return
        }

        let headers = parseRequestHeaders(from: requestString)
        let rangeHeader = headers["range"]

        // Parse query parameters (URL-decoded)
        var queryParams: [String: String] = [:]
        if let queryStart = pathAfterPrefix.range(of: "?") {
            let query = String(pathAfterPrefix[queryStart.upperBound...])
            for param in query.components(separatedBy: "&") {
                let parts = param.components(separatedBy: "=")
                if parts.count == 2 {
                    queryParams[parts[0]] = parts[1].removingPercentEncoding ?? parts[1]
                }
            }
        }

        // Session ID priority: relay's stored session > header > query param
        let sessionID = patreonSessionID ?? headers["x-session-id"] ?? queryParams["sid"]

        guard let sessionID = sessionID, !sessionID.isEmpty else {
            sendResponse(connection: connection, status: "401 Unauthorized",
                         contentType: "application/json", body: "{\"error\":\"No Patreon session. Please log in via the relay dashboard or re-pair your Apple TV.\"}")
            return
        }

        // Extract media URLs passed by the Apple TV (from feed data it already has)
        let videoURL = queryParams["video_url"]
        let audioURL = queryParams["audio_url"]
        let embedURL = queryParams["embed_url"]
        let postType = queryParams["type"] ?? ""

        log("STREAM post=\(postID) type=\(postType) session=\(sessionID == patreonSessionID ? "relay" : "client") range=\(rangeHeader ?? "none")", type: .info)
        if let e = embedURL { log("  embed: \(e.prefix(60))", type: .info) }
        if let v = videoURL { log("  video: \(v.prefix(60))", type: .info) }
        if let a = audioURL { log("  audio: \(a.prefix(60))", type: .info) }
        activeStreamCount += 1

        Task {
            do {
                let resolvedURL: URL
                let source: MediaProxyService.MediaSource
                var useRedirect = false  // Redirect instead of proxy for HLS/YouTube

                // Use URLs passed directly from the Apple TV (from feed data)
                // This avoids needing to re-fetch the post from Patreon API (which can return 403)
                if let embedStr = embedURL {
                    let lower = embedStr.lowercased()
                    if lower.contains("youtube.com") || lower.contains("youtu.be") {
                        log("YouTube embed detected, running yt-dlp...", type: .info)
                        resolvedURL = try await mediaProxy.extractWithYtdlp(urlString: embedStr)
                        source = .youtube
                        useRedirect = true  // YouTube returns HLS — let AVPlayer handle directly
                    } else if lower.contains("vimeo.com") {
                        log("Vimeo embed detected, running yt-dlp...", type: .info)
                        resolvedURL = try await mediaProxy.extractWithYtdlp(urlString: embedStr)
                        source = .vimeo
                        useRedirect = true  // Vimeo may also use HLS
                    } else if let url = URL(string: embedStr) {
                        resolvedURL = url
                        source = .directURL
                    } else {
                        throw MediaProxyService.MediaProxyError.noPlayableMedia
                    }
                } else if let videoStr = videoURL, let url = URL(string: videoStr) {
                    log("Resolving Patreon video redirect...", type: .info)
                    resolvedURL = try await mediaProxy.resolvePatreonRedirects(url: url, sessionID: sessionID)
                    source = .patreonCDN
                } else if let audioStr = audioURL, let url = URL(string: audioStr) {
                    log("Resolving Patreon audio redirect...", type: .info)
                    resolvedURL = try await mediaProxy.resolvePatreonRedirects(url: url, sessionID: sessionID)
                    source = .patreonCDN
                } else {
                    // Fallback: try fetching post data from Patreon API
                    log("No direct URLs, fetching from Patreon API...", type: .info)
                    let result = try await mediaProxy.resolveMediaURL(postID: postID, sessionID: sessionID)
                    resolvedURL = result.url
                    source = result.source
                }

                log("Resolved \(postID) via \(source.rawValue): \(resolvedURL.absoluteString.prefix(80))...", type: .success)

                if useRedirect {
                    // For YouTube/Vimeo HLS streams, redirect the client directly.
                    // AVPlayer handles HLS natively and can stream from the CDN.
                    // Proxying HLS manifests breaks because segment URLs point to the CDN.
                    log("Redirecting client to \(source.rawValue) stream", type: .info)
                    sendRedirect(connection: connection, location: resolvedURL.absoluteString)
                    activeStreamCount -= 1
                } else {
                    await proxyUpstreamMedia(
                        mediaURL: resolvedURL,
                        rangeHeader: rangeHeader,
                        sessionID: sessionID,
                        connection: connection
                    )
                }
            } catch let error as MediaProxyService.MediaProxyError {
                let (status, message) = mediaProxyErrorResponse(error)
                log("Stream error for \(postID): \(message)", type: .error)
                sendResponse(connection: connection, status: status,
                             contentType: "application/json", body: "{\"error\":\"\(message)\"}")
                activeStreamCount -= 1
            } catch {
                log("Stream error for \(postID): \(error.localizedDescription)", type: .error)
                sendResponse(connection: connection, status: "502 Bad Gateway",
                             contentType: "application/json",
                             body: "{\"error\":\"Media resolution failed: \(error.localizedDescription)\"}")
                activeStreamCount -= 1
            }
        }
    }

    private func mediaProxyErrorResponse(_ error: MediaProxyService.MediaProxyError) -> (String, String) {
        switch error {
        case .postNotFound:
            return ("404 Not Found", "Post not found")
        case .noSessionID:
            return ("401 Unauthorized", "No session ID")
        case .noPlayableMedia:
            return ("404 Not Found", "No playable media found for this post")
        case .ytdlpNotInstalled:
            return ("501 Not Implemented", "yt-dlp not installed on relay server. Install with: brew install yt-dlp")
        case .ytdlpFailed(let msg):
            let safe = msg.prefix(200).replacingOccurrences(of: "\"", with: "'")
            return ("502 Bad Gateway", "yt-dlp failed: \(safe)")
        case .resolutionFailed(let msg):
            let safe = msg.prefix(200).replacingOccurrences(of: "\"", with: "'")
            return ("502 Bad Gateway", "Resolution failed: \(safe)")
        case .upstreamError(let code):
            return ("\(code) Upstream Error", "Patreon API returned HTTP \(code)")
        }
    }

    /// Proxy upstream media response to the client connection, streaming chunks as they arrive
    private func proxyUpstreamMedia(
        mediaURL: URL,
        rangeHeader: String?,
        sessionID: String,
        connection: NWConnection
    ) async {
        var request = URLRequest(url: mediaURL)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

        // Forward Range header for seeking support
        if let range = rangeHeader {
            request.setValue(range, forHTTPHeaderField: "Range")
        }

        // If it's a Patreon URL, include session cookie
        if let host = mediaURL.host, host.contains("patreon") {
            request.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")
            request.setValue("https://www.patreon.com", forHTTPHeaderField: "Referer")
        }

        let streamDelegate = MediaStreamDelegate(
            connection: connection,
            logHandler: { [weak self] msg, type in
                Task { @MainActor in
                    self?.log(msg, type: type)
                }
            },
            onComplete: { [weak self] bytesTransferred in
                Task { @MainActor in
                    self?.activeStreamCount -= 1
                    self?.totalBytesProxied += bytesTransferred
                }
            }
        )

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 7200 // 2 hours for long videos
        let session = URLSession(configuration: config, delegate: streamDelegate, delegateQueue: nil)

        let task = session.dataTask(with: request)
        task.resume()

        // Delegate handles everything from here — streaming, cleanup, session invalidation
    }

    // MARK: - Cleanup

    func cleanupExpiredSessions() {
        let expired = pairingSessions.filter { $0.value.isExpired }
        for (code, _) in expired {
            pairingSessions.removeValue(forKey: code)
            log("Cleaned up expired session: \(code)", type: .info)
        }
        MediaProxyService.shared.clearExpiredCache()
    }
}

// MARK: - Media Stream Delegate

/// URLSessionDataDelegate that receives upstream media data and forwards it
/// chunk-by-chunk to an NWConnection (the Apple TV client).
/// Handles response header forwarding, body streaming, and cleanup.
private class MediaStreamDelegate: NSObject, URLSessionDataDelegate {
    let connection: NWConnection
    let logHandler: (String, RelayServerManager.LogEntry.LogType) -> Void
    let onComplete: (UInt64) -> Void
    private var headersSent = false
    private var bytesTransferred: UInt64 = 0
    private weak var urlSession: URLSession?

    init(
        connection: NWConnection,
        logHandler: @escaping (String, RelayServerManager.LogEntry.LogType) -> Void,
        onComplete: @escaping (UInt64) -> Void
    ) {
        self.connection = connection
        self.logHandler = logHandler
        self.onComplete = onComplete
    }

    // Received initial response headers from upstream — forward to client
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.urlSession = session

        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }

        let statusCode = httpResponse.statusCode
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)

        // Build HTTP response headers to forward
        var responseHeader = "HTTP/1.1 \(statusCode) \(statusText)\r\n"

        // Forward essential media headers
        let forwardKeys: Set<String> = ["content-type", "content-length", "content-range", "accept-ranges"]
        for (key, value) in httpResponse.allHeaderFields {
            let keyStr = "\(key)".lowercased()
            if forwardKeys.contains(keyStr) {
                responseHeader += "\(key): \(value)\r\n"
            }
        }

        responseHeader += "Access-Control-Allow-Origin: *\r\n"
        responseHeader += "Connection: close\r\n"
        responseHeader += "\r\n"

        let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length") ?? "?"
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "?"
        logHandler("Upstream \(statusCode) \(contentType) (\(contentLength) bytes)", .info)

        // Send response headers to the client
        connection.send(content: responseHeader.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logHandler("Error sending headers: \(error)", .error)
                self?.cleanup(session: session)
            }
        })

        headersSent = true
        completionHandler(.allow)
    }

    // Received a chunk of data from upstream — forward to client
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        bytesTransferred += UInt64(data.count)

        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logHandler("Client disconnected: \(error)", .warning)
                // Client disconnected — cancel upstream to stop wasting bandwidth
                dataTask.cancel()
                self?.cleanup(session: session)
            }
        })
    }

    // Upstream request completed (or failed)
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            let nsError = error as NSError
            // Don't log cancellation as error (happens when client disconnects)
            if nsError.code != NSURLErrorCancelled {
                logHandler("Upstream error: \(error.localizedDescription)", .warning)
            }
            if !headersSent {
                let errorResponse = "HTTP/1.1 502 Bad Gateway\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{\"error\":\"Upstream request failed\"}"
                connection.send(content: errorResponse.data(using: .utf8), completion: .contentProcessed { _ in })
            }
        }

        let formatted = ByteCountFormatter.string(fromByteCount: Int64(bytesTransferred), countStyle: .file)
        logHandler("Stream complete: \(formatted) transferred", .success)
        cleanup(session: session)
    }

    private func cleanup(session: URLSession) {
        connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.connection.cancel()
        })
        session.finishTasksAndInvalidate()
        onComplete(bytesTransferred)
    }
}
