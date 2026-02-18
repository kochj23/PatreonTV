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

/// Wraps AVPlayerViewController for full-screen native tvOS playback.
/// Provides transport controls, Siri Remote scrubbing, and skip buttons.
struct FullScreenPlayerView: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        return vc
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.player = player
    }
}

struct PostDetailView: View {
    let post: PatreonPost
    var allPosts: [PatreonPost]?  // Feed context for Up Next
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var showFullScreenPlayer = false
    @State private var mediaError: String?
    @State private var isLoadingMedia = false
    @State private var playerStatusObserver: NSKeyValueObservation?
    @State private var progressTimeObserver: Any?
    @State private var endOfPlaybackObserver: NSObjectProtocol?
    @State private var showDebugLog = false
    // Up Next state
    @State private var showUpNext = false
    @State private var upNextPost: PatreonPost?
    @State private var upNextCountdown = 10
    @State private var upNextTimer: Timer?
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
        .fullScreenCover(isPresented: $showFullScreenPlayer) {
            ZStack {
                if let player = player {
                    FullScreenPlayerView(player: player)
                        .ignoresSafeArea()
                }

                // Up Next overlay
                if showUpNext, let nextPost = upNextPost {
                    UpNextOverlayView(
                        nextPost: nextPost,
                        countdown: upNextCountdown,
                        onPlayNow: { playNextPost(nextPost) },
                        onCancel: { cancelUpNext() }
                    )
                }
            }
        }
        .onAppear {
            debugLog.log("PostDetailView appeared for post \(post.id) type=\(post.postType.rawValue)")
        }
        .onDisappear {
            // Save final playback position before cleanup
            if let currentTime = player?.currentTime().seconds,
               let duration = player?.currentItem?.duration.seconds,
               duration.isFinite, duration > 0 {
                PlaybackProgressManager.shared.save(
                    postID: post.id,
                    position: currentTime,
                    duration: duration
                )
            }
            // Clean up Up Next
            upNextTimer?.invalidate()
            upNextTimer = nil
            // Remove end-of-playback observer
            if let observer = endOfPlaybackObserver {
                NotificationCenter.default.removeObserver(observer)
                endOfPlaybackObserver = nil
            }
            // Remove periodic time observer
            if let observer = progressTimeObserver {
                player?.removeTimeObserver(observer)
                progressTimeObserver = nil
            }
            playerStatusObserver?.invalidate()
            playerStatusObserver = nil
            player?.pause()
            player = nil
        }
    }

    // MARK: - Media Player View

    @ViewBuilder
    private var mediaPlayerView: some View {
        if player != nil {
            // Show a compact "Now Playing" bar — full-screen player is in the fullScreenCover
            HStack(spacing: 16) {
                Image(systemName: post.hasAudio ? "waveform" : "film")
                    .font(.system(size: 24))
                    .foregroundStyle(.white)
                VStack(alignment: .leading) {
                    Text(isPlaying ? "Now Playing" : "Loading...")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(post.displayTitle)
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    showFullScreenPlayer = true
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 20))
                }
                .buttonStyle(.bordered)
            }
            .padding(24)
            .background(Color.black.opacity(0.6))
            .cornerRadius(12)
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
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(PatreonColors.yellow)
                        Text(error)
                            .font(.system(size: 16, design: .monospaced))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.leading)
                            .padding(.horizontal, 20)
                        Button {
                            mediaError = nil
                            isLoadingMedia = true
                            loadAndPlayMedia()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                                .font(.system(size: 20, weight: .semibold))
                        }
                        .buttonStyle(.bordered)
                        .tint(.white)
                    }
                    .padding(20)
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
        debugLog.log("  videoURL: \(post.videoURL ?? "nil")")
        debugLog.log("  audioURL: \(post.audioURL ?? "nil")")
        debugLog.log("  embedURL: \(post.embedURL ?? "nil")")

        // Get relay server info from AuthManager
        let authManager = AuthManager.shared
        guard authManager.relayDiscovered else {
            debugLog.log("ERROR: Relay server not discovered")
            isLoadingMedia = false
            mediaError = "Relay server not found. Make sure PatreonTV Relay is running on your Mac."
            return
        }

        let relayHost = authManager.relayServerHost
        let relayPort = authManager.relayServerPort

        // Build relay proxy URL with media info as query params.
        // The Apple TV already has post data from the feed, so we pass the URLs
        // directly to avoid the relay needing to re-fetch from Patreon API.
        var components = URLComponents()
        components.scheme = "http"
        components.host = relayHost
        components.port = relayPort
        components.path = "/api/media/stream/\(post.id)"

        var queryItems: [URLQueryItem] = []

        // Pass media URLs the Apple TV already has
        if let videoURL = post.videoURL {
            queryItems.append(URLQueryItem(name: "video_url", value: videoURL))
        }
        if let audioURL = post.audioURL {
            queryItems.append(URLQueryItem(name: "audio_url", value: audioURL))
        }
        if let embedURL = post.embedURL {
            queryItems.append(URLQueryItem(name: "embed_url", value: embedURL))
        }
        queryItems.append(URLQueryItem(name: "type", value: post.postType.rawValue))

        // Pass session ID as fallback (relay prefers its own stored session)
        if let sessionID = PatreonAPI.shared.sessionID {
            queryItems.append(URLQueryItem(name: "sid", value: sessionID))
        }

        components.queryItems = queryItems

        guard let streamURL = components.url else {
            debugLog.log("ERROR: Could not construct stream URL")
            isLoadingMedia = false
            mediaError = "Internal error constructing stream URL"
            return
        }

        debugLog.log("Stream URL: http://\(relayHost):\(relayPort)/api/media/stream/\(post.id)?type=\(post.postType.rawValue)&...")

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
                    self.mediaError = "Playback failed: \(errorMsg)\n\nPress Retry to try again."
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

        // Resume from saved position if available
        if let savedProgress = PlaybackProgressManager.shared.getProgress(postID: post.id) {
            let seekTime = CMTime(seconds: savedProgress.position, preferredTimescale: 1)
            debugLog.log("Resuming from saved position: \(Int(savedProgress.position))s")
            player?.seek(to: seekTime)
        }

        // Periodically save playback position (every 5 seconds)
        progressTimeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { [postID = post.id] time in
            guard let duration = self.player?.currentItem?.duration.seconds,
                  duration.isFinite, duration > 0 else { return }
            PlaybackProgressManager.shared.save(
                postID: postID,
                position: time.seconds,
                duration: duration
            )
        }

        // Register end-of-playback observer for Up Next
        endOfPlaybackObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [postID = post.id] _ in
            // Mark as fully watched
            PlaybackProgressManager.shared.removeProgress(postID: postID)

            // Find next playable post in feed
            if let allPosts = self.allPosts,
               let currentIndex = allPosts.firstIndex(where: { $0.id == postID }),
               currentIndex + 1 < allPosts.count {
                let nextCandidate = allPosts[(currentIndex + 1)...]
                if let nextPlayable = nextCandidate.first(where: { $0.hasVideo || $0.hasAudio }) {
                    self.upNextPost = nextPlayable
                    self.upNextCountdown = 10
                    self.showUpNext = true
                    self.startUpNextCountdown()
                }
            }
        }

        // Auto-present full-screen player
        showFullScreenPlayer = true
    }

    // MARK: - Up Next

    private func startUpNextCountdown() {
        upNextTimer?.invalidate()
        upNextTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.upNextCountdown > 1 {
                    self.upNextCountdown -= 1
                } else {
                    // Countdown finished — auto-play next
                    if let nextPost = self.upNextPost {
                        self.playNextPost(nextPost)
                    }
                }
            }
        }
    }

    private func playNextPost(_ nextPost: PatreonPost) {
        cancelUpNext()

        // Stop current player
        player?.pause()
        if let observer = progressTimeObserver {
            player?.removeTimeObserver(observer)
            progressTimeObserver = nil
        }
        if let observer = endOfPlaybackObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfPlaybackObserver = nil
        }
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        player = nil
        isPlaying = false
        showFullScreenPlayer = false

        // Dismiss current view — the parent will present the next post
        // For now, dismiss and let the feed handle navigation
        dismiss()

        // Post notification so FeedView can auto-open the next post
        NotificationCenter.default.post(
            name: Notification.Name("PlayNextPost"),
            object: nil,
            userInfo: ["postID": nextPost.id]
        )
    }

    private func cancelUpNext() {
        upNextTimer?.invalidate()
        upNextTimer = nil
        showUpNext = false
        upNextPost = nil
    }
}

// MARK: - Up Next Overlay View

struct UpNextOverlayView: View {
    let nextPost: PatreonPost
    let countdown: Int
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            HStack(spacing: 24) {
                // Next post info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Up Next in \(countdown)...")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)

                    Text(nextPost.displayTitle)
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(2)

                    if let campaign = nextPost.campaign {
                        Text(campaign.name)
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                Spacer()

                // Thumbnail
                if let thumbnailURL = nextPost.thumbnailURL ?? nextPost.imageURL,
                   let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 200, height: 112)
                    .cornerRadius(8)
                }

                // Buttons
                VStack(spacing: 12) {
                    Button(action: onPlayNow) {
                        Label("Play Now", systemImage: "play.fill")
                            .font(.system(size: 20, weight: .semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.system(size: 18))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(30)
            .background(.ultraThinMaterial)
            .cornerRadius(16)
            .padding(.horizontal, 60)
            .padding(.bottom, 40)
        }
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
