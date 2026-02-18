//
//  MediaProxyService.swift
//  PatreonTV Relay
//
//  Media URL resolution and streaming proxy service.
//  Resolves Patreon media URLs (redirect following with session cookie)
//  and YouTube/Vimeo embeds (via yt-dlp) for streaming to Apple TV.
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import Foundation

/// Manages media URL resolution, yt-dlp integration, and URL caching
/// for the streaming proxy endpoint.
@MainActor
class MediaProxyService: ObservableObject {
    static let shared = MediaProxyService()

    // MARK: - Published State (for relay UI)

    @Published var activeStreams: Int = 0
    @Published var ytdlpAvailable: Bool = false
    @Published var ytdlpPath: String?
    @Published var cacheHits: Int = 0
    @Published var cacheMisses: Int = 0

    // MARK: - URL Cache

    struct CachedMedia {
        let url: URL
        let source: MediaSource
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > 300 // 5 minutes
        }
    }

    enum MediaSource: String {
        case patreonCDN = "Patreon CDN"
        case youtube = "YouTube (yt-dlp)"
        case vimeo = "Vimeo (yt-dlp)"
        case directURL = "Direct URL"
    }

    enum MediaProxyError: Error, LocalizedError {
        case postNotFound
        case noSessionID
        case noPlayableMedia
        case ytdlpNotInstalled
        case ytdlpFailed(String)
        case resolutionFailed(String)
        case upstreamError(Int)

        var errorDescription: String? {
            switch self {
            case .postNotFound:
                return "Post not found"
            case .noSessionID:
                return "No session ID provided"
            case .noPlayableMedia:
                return "No playable media found for this post"
            case .ytdlpNotInstalled:
                return "yt-dlp is not installed on the relay server. Install with: brew install yt-dlp"
            case .ytdlpFailed(let msg):
                return "yt-dlp failed: \(msg)"
            case .resolutionFailed(let msg):
                return "Media resolution failed: \(msg)"
            case .upstreamError(let code):
                return "Patreon API returned HTTP \(code)"
            }
        }
    }

    private var urlCache: [String: CachedMedia] = [:]

    private init() {
        detectYtdlp()
    }

    // MARK: - yt-dlp Detection

    func detectYtdlp() {
        let paths = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp"]
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                ytdlpPath = path
                ytdlpAvailable = true
                print("[MediaProxy] yt-dlp found at \(path)")
                return
            }
        }
        ytdlpAvailable = false
        print("[MediaProxy] yt-dlp not found")
    }

    // MARK: - Cache Management

    func cachedURL(forPostID postID: String) -> CachedMedia? {
        guard let cached = urlCache[postID], !cached.isExpired else {
            urlCache.removeValue(forKey: postID)
            return nil
        }
        cacheHits += 1
        return cached
    }

    private func cacheURL(_ url: URL, source: MediaSource, forPostID postID: String) {
        cacheMisses += 1
        urlCache[postID] = CachedMedia(url: url, source: source, timestamp: Date())
    }

    func clearExpiredCache() {
        urlCache = urlCache.filter { !$0.value.isExpired }
    }

    // MARK: - Main Entry Point

    /// Resolve a post ID to a streamable media URL.
    /// Returns the resolved URL and its source type.
    func resolveMediaURL(postID: String, sessionID: String) async throws -> (url: URL, source: MediaSource) {
        // Check cache first
        if let cached = cachedURL(forPostID: postID) {
            print("[MediaProxy] Cache hit for post \(postID): \(cached.source.rawValue)")
            return (cached.url, cached.source)
        }

        print("[MediaProxy] Cache miss for post \(postID), resolving...")

        // Fetch post data from Patreon API
        let postData = try await fetchPostData(postID: postID, sessionID: sessionID)

        // Resolve to a streamable URL
        let (url, source) = try await resolveFromPostData(postData, sessionID: sessionID)

        // Cache the result
        cacheURL(url, source: source, forPostID: postID)

        print("[MediaProxy] Resolved post \(postID) via \(source.rawValue): \(url.absoluteString.prefix(80))...")
        return (url, source)
    }

    // MARK: - Patreon API Fetch

    /// Minimal struct holding what we need for media resolution
    struct PostMediaData {
        let postType: String
        let embedURL: String?
        let videoURL: String?
        let audioURL: String?
        let title: String?
    }

    private func fetchPostData(postID: String, sessionID: String) async throws -> PostMediaData {
        let urlString = "https://www.patreon.com/api/posts/\(postID)"
            + "?include=campaign,attachments_media,post_file,audio,media,images"
            + "&fields[post]=title,post_type,embed_url,post_file,url,embed"
            + "&fields[media]=download_url,image_urls,media_type,file_name,metadata"
            + "&fields[campaign]=name"

        guard let url = URL(string: urlString) else {
            throw MediaProxyError.resolutionFailed("Invalid API URL")
        }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.patreon.com", forHTTPHeaderField: "Referer")
        request.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaProxyError.resolutionFailed("Invalid response")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw MediaProxyError.upstreamError(httpResponse.statusCode)
        }

        return try parsePostMediaData(from: data)
    }

    // MARK: - JSON Parsing

    private func parsePostMediaData(from data: Data) throws -> PostMediaData {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let postData = json["data"] as? [String: Any],
              let attrs = postData["attributes"] as? [String: Any] else {
            throw MediaProxyError.postNotFound
        }

        let postType = attrs["post_type"] as? String ?? ""
        let title = attrs["title"] as? String
        var embedURL = attrs["embed_url"] as? String

        // Parse embed.html iframe src if embed_url is nil
        if embedURL == nil, let embed = attrs["embed"] as? [String: Any],
           let html = embed["html"] as? String {
            if let range = html.range(of: "src=\"", options: .caseInsensitive),
               let endRange = html[range.upperBound...].range(of: "\"") {
                embedURL = String(html[range.upperBound..<endRange.lowerBound])
            }
        }

        // Build media lookups from included items
        var mediaLookup: [String: String] = [:]
        var mediaTypeLookup: [String: String] = [:]

        if let included = json["included"] as? [[String: Any]] {
            for item in included {
                guard item["type"] as? String == "media",
                      let itemID = item["id"] as? String,
                      let itemAttrs = item["attributes"] as? [String: Any] else { continue }

                if let mediaType = itemAttrs["media_type"] as? String {
                    mediaTypeLookup[itemID] = mediaType
                }
                if let downloadURL = itemAttrs["download_url"] as? String {
                    mediaLookup[itemID] = downloadURL
                }
            }
        }

        // Helper: check if media is video/audio (not image thumbnail)
        func isVideoMedia(_ mediaId: String) -> Bool {
            if let mediaType = mediaTypeLookup[mediaId] {
                return !mediaType.hasPrefix("image/")
            }
            if let url = mediaLookup[mediaId]?.lowercased() {
                let imageExts = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg"]
                return !imageExts.contains(where: { url.contains($0) })
            }
            return true
        }

        // Extract video/audio from relationships
        var videoURL: String?
        var audioURL: String?
        let relationships = postData["relationships"] as? [String: Any]

        // 1. post_file relationship
        if let postFile = relationships?["post_file"] as? [String: Any],
           let fileData = postFile["data"] as? [String: Any],
           let fileID = fileData["id"] as? String,
           isVideoMedia(fileID) {
            videoURL = mediaLookup[fileID]
        }

        // 2. media relationship
        if videoURL == nil, let media = relationships?["media"] as? [String: Any],
           let mediaData = media["data"] as? [[String: Any]] {
            for ref in mediaData {
                if let refID = ref["id"] as? String, isVideoMedia(refID),
                   let url = mediaLookup[refID] {
                    videoURL = url
                    break
                }
            }
        }

        // 3. attachments_media
        if videoURL == nil, let attachments = relationships?["attachments_media"] as? [String: Any],
           let attachData = attachments["data"] as? [[String: Any]] {
            for ref in attachData {
                if let refID = ref["id"] as? String, isVideoMedia(refID),
                   let url = mediaLookup[refID] {
                    videoURL = url
                    break
                }
            }
        }

        // 4. audio relationship
        if let audio = relationships?["audio"] as? [String: Any],
           let audioData = audio["data"] as? [String: Any],
           let audioID = audioData["id"] as? String {
            audioURL = mediaLookup[audioID]
        }

        return PostMediaData(
            postType: postType,
            embedURL: embedURL,
            videoURL: videoURL,
            audioURL: audioURL,
            title: title
        )
    }

    // MARK: - Resolve from Post Data

    private func resolveFromPostData(_ postData: PostMediaData, sessionID: String) async throws -> (URL, MediaSource) {
        // 1. Patreon-hosted video (needs redirect resolution)
        if let videoURLStr = postData.videoURL, let videoURL = URL(string: videoURLStr) {
            print("[MediaProxy] Resolving Patreon video URL: \(videoURLStr.prefix(80))")
            let resolved = try await resolvePatreonRedirects(url: videoURL, sessionID: sessionID)
            return (resolved, .patreonCDN)
        }

        // 2. Patreon-hosted audio
        if let audioURLStr = postData.audioURL, let audioURL = URL(string: audioURLStr) {
            print("[MediaProxy] Resolving Patreon audio URL: \(audioURLStr.prefix(80))")
            let resolved = try await resolvePatreonRedirects(url: audioURL, sessionID: sessionID)
            return (resolved, .patreonCDN)
        }

        // 3. Embed URL — YouTube/Vimeo use yt-dlp, others try direct
        if let embedURLStr = postData.embedURL {
            let lower = embedURLStr.lowercased()

            if lower.contains("youtube.com") || lower.contains("youtu.be") {
                print("[MediaProxy] YouTube embed detected, running yt-dlp...")
                let directURL = try await extractWithYtdlp(urlString: embedURLStr)
                return (directURL, .youtube)
            }

            if lower.contains("vimeo.com") {
                print("[MediaProxy] Vimeo embed detected, running yt-dlp...")
                let directURL = try await extractWithYtdlp(urlString: embedURLStr)
                return (directURL, .vimeo)
            }

            // Try as direct URL
            if let url = URL(string: embedURLStr) {
                return (url, .directURL)
            }
        }

        throw MediaProxyError.noPlayableMedia
    }

    // MARK: - Patreon Redirect Resolution

    /// Resolve a Patreon media URL by following the redirect with session cookie.
    /// The redirect target is a CDN URL that doesn't need authentication.
    func resolvePatreonRedirects(url: URL, sessionID: String) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.patreon.com", forHTTPHeaderField: "Referer")
        request.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")

        let delegate = RedirectCapture()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        do {
            let (_, response) = try await session.data(for: request)

            // If we captured a redirect, use that (it's the CDN URL)
            if let redirectURL = delegate.capturedRedirectURL {
                print("[MediaProxy] Redirect captured → \(redirectURL.host ?? "?"):\(redirectURL.pathExtension)")
                return redirectURL
            }

            // If response is HLS, use original URL
            if let httpResp = response as? HTTPURLResponse,
               let contentType = httpResp.value(forHTTPHeaderField: "Content-Type"),
               (contentType.contains("mpegurl") || contentType.contains("x-mpegURL")) {
                return url
            }

            // No redirect — return original
            return url

        } catch let error as URLError where error.code == .cancelled {
            // Redirect blocking causes cancellation — check if we captured the URL
            if let redirectURL = delegate.capturedRedirectURL {
                return redirectURL
            }
            throw error
        }
    }

    // MARK: - yt-dlp Extraction

    // MARK: - User Agent Rotation (Anti-Detection)

    /// Rotating user agents to avoid YouTube throttling/blocking yt-dlp.
    /// YouTube actively fingerprints yt-dlp requests and throttles them.
    private static let userAgents = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.3 Safari/605.1.15",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:123.0) Gecko/20100101 Firefox/123.0",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36 Edg/121.0.0.0",
    ]

    private func randomUserAgent() -> String {
        Self.userAgents.randomElement() ?? Self.userAgents[0]
    }

    /// Extract a direct stream URL from a YouTube/Vimeo URL using yt-dlp.
    /// Runs as a subprocess on the Mac.
    /// Uses anti-detection measures: rotated user agents, web player client,
    /// and referer headers to avoid YouTube throttling.
    func extractWithYtdlp(urlString: String) async throws -> URL {
        guard let ytdlpPath = ytdlpPath else {
            throw MediaProxyError.ytdlpNotInstalled
        }

        let userAgent = randomUserAgent()

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: ytdlpPath)
                process.arguments = [
                    "-g",                                    // Print URL only
                    "-f", "best[ext=mp4]/best",              // Prefer MP4 for Apple TV compatibility
                    "--user-agent", userAgent,                // Rotated browser UA
                    "--referer", "https://www.youtube.com/",  // Look like a browser referral
                    "--extractor-args", "youtube:player_client=web", // Use web client (less fingerprinted)
                    "--no-check-certificates",               // Avoid cert issues
                    "--no-warnings",                         // Clean output
                    "--socket-timeout", "15",                // Don't hang forever
                    urlString
                ]

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    if process.terminationStatus == 0 {
                        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                        if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           let url = URL(string: output) {
                            print("[MediaProxy] yt-dlp resolved (UA: \(userAgent.prefix(30))...): \(output.prefix(80))...")
                            continuation.resume(returning: url)
                        } else {
                            continuation.resume(throwing: MediaProxyError.ytdlpFailed("No URL in yt-dlp output"))
                        }
                    } else {
                        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        print("[MediaProxy] yt-dlp failed (exit \(process.terminationStatus)): \(errorStr.prefix(200))")
                        continuation.resume(throwing: MediaProxyError.ytdlpFailed(String(errorStr.prefix(500))))
                    }
                } catch {
                    continuation.resume(throwing: MediaProxyError.ytdlpFailed(error.localizedDescription))
                }
            }
        }
    }
}

// MARK: - Redirect Capture Delegate

/// URLSession delegate that captures the redirect URL and blocks the redirect.
/// This extracts the CDN URL without actually following it (avoiding full download).
private class RedirectCapture: NSObject, URLSessionTaskDelegate {
    var capturedRedirectURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let redirectURL = request.url {
            capturedRedirectURL = redirectURL
            print("[MediaProxy] Captured redirect: \(redirectURL.host ?? "?") ext=\(redirectURL.pathExtension)")
        }
        // Block the redirect — we only need the URL
        completionHandler(nil)
    }
}
