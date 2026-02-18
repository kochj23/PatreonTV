//
//  PostDetailView.swift
//  PatreonTV
//
//  Detailed view for a single post with video/audio playback
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI
import AVKit

// MARK: - Debug Log Buffer

/// In-memory log buffer that captures debug messages for on-screen display.
/// Since we can't easily read Apple TV console logs, this renders on the TV.
/// Global singleton debug logger that writes to a file in the app container.
/// Pull with: xcrun devicectl device copy from --device <ID> --source Documents/debug_log.txt --destination /tmp/debug.txt --domain-type appDataContainer --domain-identifier com.jordankoch.patreontv
/// Global debug logger — writes every message to Documents/debug_log.txt
/// Pull with: xcrun devicectl device copy from --device <ID> --source Documents/debug_log.txt --destination /tmp/debug.txt --domain-type appDataContainer --domain-identifier com.jordankoch.patreontv
class DebugLog: ObservableObject {
    static let shared: DebugLog = {
        let instance = DebugLog()
        instance.log("DebugLog singleton created")
        return instance
    }()

    @Published var entries: [String] = []

    private static var logFileURL: URL = {
        let tmp = FileManager.default.temporaryDirectory
        return tmp.appendingPathComponent("debug_log.txt")
    }()

    init() {
        // Create/clear the log file immediately in tmp dir
        let url = DebugLog.logFileURL
        let header = "=== PatreonTV Debug Log ===\nPath: \(url.path)\n"
        FileManager.default.createFile(atPath: url.path, contents: header.data(using: .utf8))
        print("[DebugLog] Log file: \(url.path)")
    }

    /// Static write function that works even before singleton is accessed
    static func writeToFile(_ message: String) {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        let entry = "[\(df.string(from: Date()))] \(message)\n"
        if let handle = FileHandle(forWritingAtPath: logFileURL.path) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8)!)
            handle.closeFile()
        } else {
            // File doesn't exist yet, create it
            FileManager.default.createFile(atPath: logFileURL.path, contents: entry.data(using: .utf8))
        }
    }

    func log(_ message: String) {
        print("[PostDetail] \(message)")
        DebugLog.writeToFile(message)

        DispatchQueue.main.async {
            self.entries.append(message)
            if self.entries.count > 100 {
                self.entries.removeFirst(self.entries.count - 100)
            }
        }
    }

    var fullText: String {
        entries.joined(separator: "\n")
    }
}

// MARK: - PostDetailView

struct PostDetailView: View {
    let post: PatreonPost
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var mediaError: String?
    @State private var isLoadingMedia = false
    @State private var playerStatusObserver: NSKeyValueObservation?
    @State private var showDebugLog = false
    @ObservedObject private var debugLog = DebugLog.shared

    var body: some View {
        NavigationStack {
            ZStack {
                GlassmorphicBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Media area — video/audio/image
                        if post.hasVideo || post.hasAudio {
                            mediaPlayerView
                        } else if let imageURL = post.imageURL,
                                  let url = URL(string: imageURL) {
                            AsyncImage(url: url) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } placeholder: {
                                ProgressView()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(maxHeight: 500)
                            .cornerRadius(12)
                        }

                        // Post metadata row
                        HStack(spacing: 14) {
                            if let campaign = post.campaign {
                                if let avatarURL = campaign.avatarURL,
                                   let url = URL(string: avatarURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Circle()
                                            .fill(Color.gray.opacity(0.3))
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                }

                                Text(campaign.name)
                                    .font(.system(size: 20))
                                    .foregroundStyle(PatreonColors.textSecondary)
                            }

                            if let date = post.publishedAt {
                                Text("·")
                                    .foregroundStyle(PatreonColors.textTertiary)
                                Text(date, style: .date)
                                    .font(.system(size: 18))
                                    .foregroundStyle(PatreonColors.textTertiary)
                            }

                            Spacer()

                            HStack(spacing: 16) {
                                if post.likeCount > 0 {
                                    Label("\(post.likeCount)", systemImage: "heart.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(PatreonColors.textSecondary)
                                }
                                if post.commentCount > 0 {
                                    Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(PatreonColors.textSecondary)
                                }
                            }
                        }

                        // Title
                        Text(post.displayTitle)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(PatreonColors.textPrimary)
                            .lineLimit(3)

                        // Content
                        if let content = post.content {
                            let strippedContent = content.replacingOccurrences(
                                of: "<[^>]+>",
                                with: "",
                                options: .regularExpression
                            )
                            if !strippedContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(strippedContent)
                                    .font(.system(size: 20))
                                    .foregroundStyle(PatreonColors.textSecondary)
                                    .lineSpacing(6)
                            }
                        }

                        // Debug log section — always visible when there are entries
                        if !debugLog.entries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Button {
                                    showDebugLog.toggle()
                                } label: {
                                    HStack {
                                        Image(systemName: "ladybug.fill")
                                        Text(showDebugLog ? "Hide Debug Log" : "Show Debug Log (\(debugLog.entries.count) entries)")
                                    }
                                    .font(.system(size: 16))
                                }
                                .buttonStyle(.bordered)

                                if showDebugLog {
                                    Text(debugLog.fullText)
                                        .font(.system(size: 14, design: .monospaced))
                                        .foregroundStyle(.green)
                                        .padding(16)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.black.opacity(0.85))
                                        .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                    .frame(maxWidth: 1200)
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            debugLog.log("PostDetailView appeared for post \(post.id) type=\(post.postType.rawValue)")
        }
        .onDisappear {
            playerStatusObserver?.invalidate()
            playerStatusObserver = nil
            player?.pause()
            player = nil
        }
    }

    // MARK: - Media Player View

    @ViewBuilder
    private var mediaPlayerView: some View {
        if let player = player {
            VideoPlayer(player: player)
                .frame(height: 500)
                .cornerRadius(12)
                .onAppear {
                    player.play()
                }
        } else {
            ZStack {
                // Background thumbnail
                if let thumbnailURL = post.thumbnailURL ?? post.imageURL,
                   let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.2))
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay {
                            Image(systemName: post.hasAudio ? "waveform" : "play.rectangle.fill")
                                .font(.system(size: 50))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                }

                // Overlay: error, loading, or play button
                if let error = mediaError {
                    ScrollView {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(PatreonColors.yellow)
                            Text(error)
                                .font(.system(size: 16, design: .monospaced))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .padding(.horizontal, 20)
                        }
                        .padding(20)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.black.opacity(0.85))
                } else if isLoadingMedia {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading media...")
                            .font(.system(size: 20))
                            .foregroundStyle(.white)
                    }
                    .padding(24)
                    .background(.black.opacity(0.7))
                    .cornerRadius(16)
                } else {
                    Button {
                        isLoadingMedia = true
                        loadAndPlayMedia()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: post.hasAudio ? "waveform.circle.fill" : "play.fill")
                                .font(.system(size: 28))
                            Text(post.hasAudio ? "Play Audio" : "Play Video")
                                .font(.system(size: 24, weight: .semibold))
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
            }
            .frame(height: 500)
            .clipped()
            .cornerRadius(12)
        }
    }

    // MARK: - Load and Play Media (via Relay Proxy)

    /// Plays media through the relay server's streaming proxy.
    /// The relay handles all URL resolution (Patreon redirects, YouTube/yt-dlp).
    /// The Apple TV just plays the relay proxy URL.
    private func loadAndPlayMedia() {
        mediaError = nil

        debugLog.log("=== loadAndPlayMedia (relay proxy) ===")
        debugLog.log("Post ID: \(post.id), type: \(post.postType.rawValue)")

        // Get relay server info from AuthManager
        let authManager = AuthManager.shared
        guard authManager.relayDiscovered else {
            debugLog.log("ERROR: Relay server not discovered")
            isLoadingMedia = false
            mediaError = "Relay server not found. Make sure PatreonTV Relay is running on your Mac."
            return
        }

        guard let sessionID = PatreonAPI.shared.sessionID else {
            debugLog.log("ERROR: No session ID")
            isLoadingMedia = false
            mediaError = "Not authenticated. Please log in again."
            return
        }

        let relayHost = authManager.relayServerHost
        let relayPort = authManager.relayServerPort

        // Construct relay proxy URL with session ID as query param
        // (query param is more reliable than custom headers on tvOS AVPlayer)
        let streamURLString = "http://\(relayHost):\(relayPort)/api/media/stream/\(post.id)?sid=\(sessionID)"
        guard let streamURL = URL(string: streamURLString) else {
            debugLog.log("ERROR: Could not construct stream URL")
            isLoadingMedia = false
            mediaError = "Internal error constructing stream URL"
            return
        }

        debugLog.log("Stream URL: http://\(relayHost):\(relayPort)/api/media/stream/\(post.id)?sid=<redacted>")

        // Create AVPlayer pointing at the relay proxy
        let asset = AVURLAsset(url: streamURL)
        let playerItem = AVPlayerItem(asset: asset)

        // Observe player item status for errors
        playerStatusObserver = playerItem.observe(\.status, options: [.new, .initial]) { item, _ in
            DispatchQueue.main.async {
                switch item.status {
                case .failed:
                    let errorMsg = item.error?.localizedDescription ?? "Unknown error"
                    let nsError = item.error as NSError?
                    self.debugLog.log("AVPlayerItem FAILED: \(errorMsg)")
                    if let domain = nsError?.domain {
                        self.debugLog.log("  domain: \(domain) code: \(nsError?.code ?? -1)")
                    }
                    if let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError {
                        self.debugLog.log("  underlying: \(underlying.domain) code=\(underlying.code)")
                    }
                    self.player?.pause()
                    self.player = nil
                    self.isPlaying = false
                    self.showDebugLog = true
                    self.mediaError = "Playback failed: \(errorMsg)"
                case .readyToPlay:
                    self.debugLog.log("AVPlayerItem READY — duration: \(item.duration.seconds)s")
                case .unknown:
                    self.debugLog.log("AVPlayerItem status: unknown (loading...)")
                @unknown default:
                    break
                }
            }
        }

        player = AVPlayer(playerItem: playerItem)
        debugLog.log("AVPlayer created, calling play()")
        player?.play()
        isPlaying = true
        isLoadingMedia = false
    }
}

// MARK: - Preview

#Preview {
    PostDetailView(post: PatreonPost(
        id: "1",
        title: "Sample Video Post",
        content: "<p>This is the full content of the post with <b>some HTML</b> formatting.</p>",
        publishedAt: Date(),
        postType: .video,
        likeCount: 42,
        commentCount: 12,
        campaign: PatreonCampaign(
            id: "1",
            name: "Sample Creator",
            avatarURL: nil
        )
    ))
}
