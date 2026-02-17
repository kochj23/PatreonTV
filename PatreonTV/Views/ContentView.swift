//
//  ContentView.swift
//  PatreonTV
//
//  Main content view that switches between pairing and home screens
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                HomeView()
            } else if authManager.isPairing {
                PairingView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut, value: authManager.isAuthenticated)
        .animation(.easeInOut, value: authManager.isPairing)
    }
}

// MARK: - Welcome View

/// Initial welcome screen with option to pair
struct WelcomeView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(spacing: 60) {
            // Logo and title
            VStack(spacing: 20) {
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 120))
                    .foregroundStyle(.orange)

                Text("PatreonTV")
                    .font(.system(size: 76, weight: .bold))

                Text("Watch your favorite creators on the big screen")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            // Discovery status
            if authManager.isDiscoveringRelay {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Searching for PatreonTV Relay on your network...")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if authManager.relayDiscovered {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Relay found at \(authManager.relayServerHost):\(authManager.relayServerPort)")
                        .font(.callout)
                        .foregroundStyle(.green)
                }
            }

            // Error message
            if let error = authManager.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                    Text(error)
                        .foregroundStyle(.yellow)
                }
                .font(.callout)
                .padding(.horizontal, 30)
                .multilineTextAlignment(.center)
            }

            // Pair button
            Button {
                authManager.startPairing()
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "qrcode")
                        .font(.title2)
                    Text("Pair with Your Mac")
                        .font(.title3)
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)

            // Instructions
            VStack(spacing: 12) {
                Text("To get started:")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Run PatreonTV Relay on your Mac", systemImage: "1.circle.fill")
                    Label("Click 'Pair with Your Mac' above", systemImage: "2.circle.fill")
                    Label("Scan the QR code with your phone", systemImage: "3.circle.fill")
                    Label("Log in to Patreon", systemImage: "4.circle.fill")
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Previews

#Preview {
    ContentView()
        .environmentObject(AuthManager.shared)
}
