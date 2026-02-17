//
//  PairingView.swift
//  PatreonTV
//
//  QR code pairing screen for authentication
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct PairingView: View {
    @EnvironmentObject var authManager: AuthManager
    @State private var qrCodeImage: UIImage?

    var body: some View {
        VStack(spacing: 50) {
            // Title
            VStack(spacing: 12) {
                Text("Pair Your Account")
                    .font(.system(size: 56, weight: .bold))

                Text("Scan the QR code with your phone to log in")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // QR Code and Code Display
            HStack(spacing: 80) {
                // QR Code
                VStack(spacing: 20) {
                    if let qrImage = qrCodeImage {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 300, height: 300)
                            .background(Color.white)
                            .cornerRadius(20)
                    } else {
                        ProgressView()
                            .frame(width: 300, height: 300)
                    }

                    Text("Scan with your phone's camera")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Manual code entry option
                VStack(spacing: 20) {
                    Text("Or enter this code:")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    if let code = authManager.pairingSession?.code {
                        Text(code)
                            .font(.system(size: 72, weight: .bold, design: .monospaced))
                            .tracking(8)
                            .foregroundStyle(.orange)
                    }

                    if let url = authManager.pairingURL {
                        Text("at \(url)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Status
            statusView

            // Cancel button
            Button {
                authManager.cancelPairing()
            } label: {
                Text("Cancel")
                    .padding(.horizontal, 40)
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.3))
        .onAppear {
            generateQRCode()
        }
        .onChange(of: authManager.pairingURL) { _, newURL in
            if newURL != nil {
                generateQRCode()
            }
        }
    }

    @ViewBuilder
    private var statusView: some View {
        if let error = authManager.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(error)
                    .foregroundStyle(.red)
            }
            .font(.headline)
        } else if let session = authManager.pairingSession {
            HStack(spacing: 12) {
                switch session.status {
                case .pending:
                    ProgressView()
                    Text("Waiting for you to scan...")
                case .scanning:
                    ProgressView()
                    Text("QR code scanned, loading login...")
                case .authenticating:
                    ProgressView()
                    Text("Please log in on your phone...")
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Success!")
                case .expired:
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("Code expired")
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    Text("Authentication failed")
                }
            }
            .font(.headline)
            .foregroundStyle(.secondary)
        }
    }

    private func generateQRCode() {
        guard let urlString = authManager.pairingURL,
              let data = urlString.data(using: .utf8) else {
            return
        }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let outputImage = filter.outputImage else { return }

        // Scale up the QR code
        let scale = CGAffineTransform(scaleX: 10, y: 10)
        let scaledImage = outputImage.transformed(by: scale)

        if let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) {
            qrCodeImage = UIImage(cgImage: cgImage)
        }
    }
}

#Preview {
    PairingView()
        .environmentObject(AuthManager.shared)
}
