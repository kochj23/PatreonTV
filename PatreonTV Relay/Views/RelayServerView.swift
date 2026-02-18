//
//  RelayServerView.swift
//  PatreonTV Relay
//
//  Main view for the relay server app
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

struct RelayServerView: View {
    @EnvironmentObject var serverManager: RelayServerManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
                .padding()
                .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Main content
            HStack(spacing: 0) {
                // Left: Server info and controls
                serverInfoView
                    .frame(width: 280)
                    .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                // Right: Logs
                logsView
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.title)
                .foregroundStyle(.orange)

            VStack(alignment: .leading) {
                Text("PatreonTV Relay")
                    .font(.headline)
                Text("Authentication & Media Proxy Server")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status indicator
            HStack(spacing: 8) {
                Circle()
                    .fill(serverManager.isRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                Text(serverManager.isRunning ? "Running" : "Stopped")
                    .font(.subheadline)
                    .foregroundStyle(serverManager.isRunning ? .green : .red)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(serverManager.isRunning ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
            )
        }
    }

    // MARK: - Server Info

    private var serverInfoView: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Server URLs
            VStack(alignment: .leading, spacing: 8) {
                Text("Server URLs")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(serverManager.allLocalIPs, id: \.self) { ip in
                    HStack {
                        Text("http://\(ip):\(serverManager.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Spacer()

                        if ip == serverManager.localIP {
                            Text("Primary")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(4)
                        }

                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("http://\(ip):\(serverManager.port)", forType: .string)
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy URL")
                    }
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }

                if serverManager.allLocalIPs.isEmpty {
                    HStack {
                        Text("http://\(serverManager.localIP):\(serverManager.port)")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        Spacer()
                    }
                    .padding(10)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(6)
                }

                Text("Listening on all interfaces. Apple TV discovers this server automatically via Bonjour.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            // Active Sessions
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Active Pairing Sessions")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(serverManager.pairingSessions.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(4)
                }

                if serverManager.pairingSessions.isEmpty {
                    Text("No active sessions")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                } else {
                    ForEach(Array(serverManager.pairingSessions.keys), id: \.self) { code in
                        if let session = serverManager.pairingSessions[code] {
                            sessionRow(code: code, session: session)
                        }
                    }
                }
            }

            // Media Proxy Status
            VStack(alignment: .leading, spacing: 8) {
                Text("Media Proxy")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Active Streams")
                    Spacer()
                    Text("\(serverManager.activeStreamCount)")
                        .foregroundStyle(serverManager.activeStreamCount > 0 ? .blue : .secondary)
                        .fontWeight(serverManager.activeStreamCount > 0 ? .medium : .regular)
                }
                .font(.caption)

                HStack {
                    Text("Bytes Proxied")
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(serverManager.totalBytesProxied), countStyle: .file))
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                HStack {
                    Text("yt-dlp")
                    Spacer()
                    if MediaProxyService.shared.ytdlpAvailable {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Available")
                                .foregroundStyle(.green)
                        }
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text("Not Found")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .font(.caption)

                HStack {
                    Text("URL Cache")
                    Spacer()
                    Text("Hits: \(MediaProxyService.shared.cacheHits) / Misses: \(MediaProxyService.shared.cacheMisses)")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }

            Spacer()

            // Controls
            VStack(spacing: 12) {
                if serverManager.isRunning {
                    Button {
                        serverManager.stopServer()
                    } label: {
                        Label("Stop Server", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                } else {
                    Button {
                        Task {
                            await serverManager.startServer()
                        }
                    } label: {
                        Label("Start Server", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }

                Button {
                    serverManager.cleanupExpiredSessions()
                } label: {
                    Label("Clean Up Sessions", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            // Info
            Text("Your Apple TV will connect to this server to authenticate with Patreon.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .padding()
    }

    private func sessionRow(code: String, session: RelayServerManager.PairingSessionData) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(code)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.medium)

                Text(session.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(statusColor(for: session.status))
            }

            Spacer()

            if session.isExpired {
                Text("Expired")
                    .font(.caption2)
                    .foregroundStyle(.red)
            } else {
                Text(session.expiresAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color(nsColor: .textBackgroundColor))
        .cornerRadius(6)
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "completed": return .green
        case "authenticating", "scanning": return .blue
        case "pending": return .orange
        case "expired", "failed": return .red
        default: return .secondary
        }
    }

    // MARK: - Logs

    private var logsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Server Logs")
                    .font(.headline)

                Spacer()

                Button {
                    serverManager.logs.removeAll()
                } label: {
                    Text("Clear")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(serverManager.logs) { entry in
                        logRow(entry: entry)
                    }
                }
                .padding()
            }
        }
    }

    private func logRow(entry: RelayServerManager.LogEntry) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp, style: .time)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Image(systemName: iconForLogType(entry.type))
                .foregroundStyle(colorForLogType(entry.type))
                .font(.caption)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func iconForLogType(_ type: RelayServerManager.LogEntry.LogType) -> String {
        switch type {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }

    private func colorForLogType(_ type: RelayServerManager.LogEntry.LogType) -> Color {
        switch type {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

#Preview {
    RelayServerView()
        .environmentObject(RelayServerManager.shared)
        .frame(width: 800, height: 600)
}
