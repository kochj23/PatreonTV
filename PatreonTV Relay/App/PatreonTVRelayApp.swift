//
//  PatreonTVRelayApp.swift
//  PatreonTV Relay
//
//  macOS relay server for PatreonTV authentication
//  Runs a local HTTP server that handles the QR code auth flow
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

@main
struct PatreonTVRelayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var serverManager = RelayServerManager.shared

    var body: some Scene {
        WindowGroup {
            RelayServerView()
                .environmentObject(serverManager)
                .frame(minWidth: 500, minHeight: 400)
                .sheet(isPresented: $serverManager.showLoginSheet) {
                    if let code = serverManager.pendingLoginCode {
                        PatreonLoginView(pairingCode: code)
                            .environmentObject(serverManager)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Start the relay server automatically
        Task {
            await RelayServerManager.shared.startServer()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        RelayServerManager.shared.stopServer()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
