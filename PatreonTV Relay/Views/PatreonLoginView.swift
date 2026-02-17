//
//  PatreonLoginView.swift
//  PatreonTV Relay
//
//  WebView-based Patreon login that automatically captures the session cookie
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI
import WebKit

/// A WebView that loads Patreon login and automatically captures the session_id cookie
struct PatreonLoginWebView: NSViewRepresentable {
    let pairingCode: String
    let onSessionCaptured: (String) -> Void
    let onStatusUpdate: (String) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load Patreon login page
        if let url = URL(string: "https://www.patreon.com/login") {
            webView.load(URLRequest(url: url))
        }

        // Start polling for cookies
        context.coordinator.startCookiePolling(webView: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(pairingCode: pairingCode, onSessionCaptured: onSessionCaptured, onStatusUpdate: onStatusUpdate)
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        let pairingCode: String
        let onSessionCaptured: (String) -> Void
        let onStatusUpdate: (String) -> Void
        private var cookieTimer: Timer?
        private var hasCompleted = false

        init(pairingCode: String, onSessionCaptured: @escaping (String) -> Void, onStatusUpdate: @escaping (String) -> Void) {
            self.pairingCode = pairingCode
            self.onSessionCaptured = onSessionCaptured
            self.onStatusUpdate = onStatusUpdate
        }

        deinit {
            cookieTimer?.invalidate()
        }

        func startCookiePolling(webView: WKWebView) {
            onStatusUpdate("Waiting for Patreon login...")

            cookieTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self, weak webView] _ in
                guard let self = self, let webView = webView, !self.hasCompleted else { return }

                webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                    for cookie in cookies {
                        if cookie.name == "session_id" && cookie.domain.contains("patreon.com") {
                            guard !self.hasCompleted else { return }
                            self.hasCompleted = true
                            self.cookieTimer?.invalidate()
                            self.cookieTimer = nil

                            let sessionID = cookie.value
                            print("[PatreonLogin] Captured session_id: \(sessionID.prefix(20))...")

                            DispatchQueue.main.async {
                                self.onStatusUpdate("Session captured! Connecting to Apple TV...")
                                self.onSessionCaptured(sessionID)
                            }
                            return
                        }
                    }
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            if let url = webView.url {
                let urlString = url.absoluteString
                if urlString.contains("patreon.com/home") || urlString.contains("patreon.com/feed") {
                    onStatusUpdate("Logged in! Capturing session...")
                } else if urlString.contains("patreon.com/login") {
                    onStatusUpdate("Please log in to Patreon...")
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Check cookies after each page load
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
                guard let self = self, !self.hasCompleted else { return }

                for cookie in cookies {
                    if cookie.name == "session_id" && cookie.domain.contains("patreon.com") {
                        self.hasCompleted = true
                        self.cookieTimer?.invalidate()
                        self.cookieTimer = nil

                        let sessionID = cookie.value
                        print("[PatreonLogin] Captured session_id on navigation: \(sessionID.prefix(20))...")

                        DispatchQueue.main.async {
                            self.onStatusUpdate("Session captured! Connecting to Apple TV...")
                            self.onSessionCaptured(sessionID)
                        }
                        return
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation within Patreon
            if let url = navigationAction.request.url,
               let host = url.host {
                if host.contains("patreon.com") || host.contains("okta.com") || host.contains("google.com") || host.contains("facebook.com") || host.contains("apple.com") {
                    decisionHandler(.allow)
                    return
                }
            }
            // Allow the initial load
            decisionHandler(.allow)
        }
    }
}

/// Window that shows the Patreon login WebView
struct PatreonLoginView: View {
    let pairingCode: String
    @EnvironmentObject var serverManager: RelayServerManager
    @Environment(\.dismiss) var dismiss
    @State private var statusMessage = "Loading Patreon..."

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "lock.shield.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)

                VStack(alignment: .leading) {
                    Text("Patreon Login")
                        .font(.headline)
                    Text("Pairing code: \(pairingCode)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
            }
            .padding()
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // WebView
            PatreonLoginWebView(
                pairingCode: pairingCode,
                onSessionCaptured: { sessionToken in
                    // Complete the pairing session
                    serverManager.completePairing(code: pairingCode, sessionToken: sessionToken)

                    statusMessage = "Connected! You can close this window."

                    // Auto-close after a moment
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        dismiss()
                    }
                },
                onStatusUpdate: { status in
                    statusMessage = status
                }
            )
        }
        .frame(minWidth: 800, minHeight: 700)
    }
}
