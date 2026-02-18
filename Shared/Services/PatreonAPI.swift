//
//  PatreonAPI.swift
//  PatreonTV
//
//  Patreon API service for fetching content
//  Uses web API endpoints (same as patreon.com website)
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import Foundation

/// Service for interacting with Patreon's web API
class PatreonAPI {
    static let shared = PatreonAPI()

    // MARK: - Configuration

    private let baseURL = "https://www.patreon.com"
    private let apiBaseURL = "https://www.patreon.com/api"

    /// Session ID cookie for authentication
    var sessionID: String? {
        didSet {
            if let sessionID = sessionID {
                print("[PatreonAPI] Session ID set: \(sessionID.prefix(20))...")
            } else {
                print("[PatreonAPI] Session ID cleared")
            }
        }
    }

    /// Cached user info
    private(set) var currentUser: PatreonUser?

    // MARK: - URL Session

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }()

    private init() {}

    // MARK: - Authentication

    /// Check if we have a valid session
    var isAuthenticated: Bool {
        sessionID != nil
    }

    /// Validate the current session by fetching user info
    func validateSession() async throws -> PatreonUser {
        guard sessionID != nil else {
            throw PatreonError.notAuthenticated
        }

        let user = try await fetchCurrentUser()
        currentUser = user
        return user
    }

    /// Clear the current session
    func logout() {
        sessionID = nil
        currentUser = nil

        // Clear cookies
        if let cookies = HTTPCookieStorage.shared.cookies(for: URL(string: baseURL)!) {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
    }

    // MARK: - API Requests

    /// Create a URLRequest with authentication
    private func createRequest(url: URL, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL, forHTTPHeaderField: "Referer")

        // Add session cookie
        if let sessionID = sessionID {
            request.setValue("session_id=\(sessionID)", forHTTPHeaderField: "Cookie")
        }

        return request
    }

    /// Perform an API request and decode the response
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw PatreonError.invalidResponse
        }

        // Check for authentication errors
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw PatreonError.notAuthenticated
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            print("[PatreonAPI] HTTP Error: \(httpResponse.statusCode)")
            if let body = String(data: data, encoding: .utf8) {
                print("[PatreonAPI] Response body: \(body.prefix(500))")
            }
            throw PatreonError.httpError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(T.self, from: data)
        } catch {
            print("[PatreonAPI] Decode error: \(error)")
            if let body = String(data: data, encoding: .utf8) {
                print("[PatreonAPI] Response body: \(body.prefix(1000))")
            }
            throw PatreonError.decodingError(error)
        }
    }

    // MARK: - Debug

    /// Fetch raw post data for debugging — returns a summary of what the API returned
    func fetchPostRawDebug(id: String) async throws -> String {
        let urlString = "\(apiBaseURL)/posts/\(id)?include=campaign,attachments_media,post_file,audio,media,images&fields[post]=title,post_type,embed_url,post_file,url,post_metadata,video_preview,current_user_can_view,content,teaser,embed&fields[media]=download_url,image_urls,media_type,file_name,metadata,duration_sec,width,height&fields[campaign]=name"

        guard let url = URL(string: urlString) else { return "Invalid URL" }
        let request = createRequest(url: url)
        let (data, _) = try await session.data(for: request)

        // Parse raw JSON
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Failed to parse JSON"
        }

        var info: [String] = []

        // Dump ALL post attributes
        if let postData = json["data"] as? [String: Any] {
            if let attrs = postData["attributes"] as? [String: Any] {
                info.append("=== POST ATTRIBUTES ===")
                for (key, value) in attrs.sorted(by: { $0.key < $1.key }) {
                    let valStr = String(describing: value)
                    info.append("  \(key): \(valStr.prefix(200))")
                }
            }
            if let rels = postData["relationships"] as? [String: Any] {
                info.append("=== POST RELATIONSHIPS ===")
                for (key, value) in rels.sorted(by: { $0.key < $1.key }) {
                    let valStr = String(describing: value)
                    info.append("  \(key): \(valStr.prefix(200))")
                }
            }
        }

        // Dump ALL included items with full attributes
        if let included = json["included"] as? [[String: Any]] {
            info.append("=== INCLUDED (\(included.count) items) ===")
            for item in included {
                let type = item["type"] as? String ?? "?"
                let itemId = item["id"] as? String ?? "?"
                info.append("--- \(type) [\(itemId)] ---")
                if let attrs = item["attributes"] as? [String: Any] {
                    for (key, value) in attrs.sorted(by: { $0.key < $1.key }) {
                        let valStr = String(describing: value)
                        info.append("  \(key): \(valStr.prefix(200))")
                    }
                }
            }
        }

        if info.isEmpty {
            return "No debug data extracted"
        }

        return info.joined(separator: "\n")
    }

    // MARK: - User Endpoints

    /// Fetch the current authenticated user
    func fetchCurrentUser() async throws -> PatreonUser {
        let url = URL(string: "\(apiBaseURL)/current_user?include=memberships.campaign&fields[user]=full_name,email,image_url,thumb_url,is_creator")!
        let request = createRequest(url: url)

        struct UserResponse: Codable {
            let data: UserData

            struct UserData: Codable {
                let id: String
                let attributes: UserAttributes
            }

            struct UserAttributes: Codable {
                let fullName: String?
                let email: String?
                let imageUrl: String?
                let thumbUrl: String?
                let isCreator: Bool?

                enum CodingKeys: String, CodingKey {
                    case fullName = "full_name"
                    case email
                    case imageUrl = "image_url"
                    case thumbUrl = "thumb_url"
                    case isCreator = "is_creator"
                }
            }
        }

        let response: UserResponse = try await performRequest(request)

        return PatreonUser(
            id: response.data.id,
            fullName: response.data.attributes.fullName ?? "Unknown",
            email: response.data.attributes.email,
            imageURL: response.data.attributes.imageUrl,
            thumbURL: response.data.attributes.thumbUrl,
            isCreator: response.data.attributes.isCreator ?? false
        )
    }

    // MARK: - Feed/Stream Endpoints

    /// Fetch the user's home feed (posts from creators they support)
    func fetchHomeFeed(cursor: String? = nil, limit: Int = 20) async throws -> (posts: [PatreonPost], nextCursor: String?) {
        var urlString = "\(apiBaseURL)/stream?include=user,campaign,attachments_media,post_file,media,audio,images&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,embed,is_paid,like_count,comment_count,post_file&fields[campaign]=name,avatar_photo_url,url&fields[media]=download_url,image_urls,media_type,file_name,metadata&page[count]=\(limit)"

        if let cursor = cursor {
            urlString += "&page[cursor]=\(cursor)"
        }

        guard let url = URL(string: urlString) else {
            throw PatreonError.invalidURL
        }

        let request = createRequest(url: url)

        struct StreamResponse: Codable {
            let data: [PostData]
            let included: [IncludedItem]?
            let meta: Meta?

            struct PostData: Codable {
                let id: String
                let attributes: PostAttributes
                let relationships: PostRelationships?
            }

            struct EmbedInfo: Codable {
                let html: String?
                let description: String?
                let url: String?
            }

            struct PostAttributes: Codable {
                let title: String?
                let content: String?
                let teaser: String?
                let publishedAt: String?
                let postType: String?
                let image: ImageData?
                let thumbnailUrl: String?
                let url: String?
                let embedUrl: String?
                let embed: EmbedInfo?
                let isPaid: Bool?
                let likeCount: Int?
                let commentCount: Int?

                enum CodingKeys: String, CodingKey {
                    case title, content, teaser
                    case publishedAt = "published_at"
                    case postType = "post_type"
                    case image
                    case thumbnailUrl = "thumbnail_url"
                    case url
                    case embedUrl = "embed_url"
                    case embed
                    case isPaid = "is_paid"
                    case likeCount = "like_count"
                    case commentCount = "comment_count"
                }
            }

            struct ImageData: Codable {
                let url: String?
                let thumbUrl: String?

                enum CodingKeys: String, CodingKey {
                    case url
                    case thumbUrl = "thumb_url"
                }
            }

            struct PostRelationships: Codable {
                let campaign: RelationshipData?
                let user: RelationshipData?
                let postFile: RelationshipData?
                let attachmentsMedia: RelationshipList?
                let media: RelationshipList?
                let audio: RelationshipData?
                let images: RelationshipList?

                enum CodingKeys: String, CodingKey {
                    case campaign, user, media, audio, images
                    case postFile = "post_file"
                    case attachmentsMedia = "attachments_media"
                }
            }

            struct RelationshipData: Codable {
                let data: RelationshipItem?
            }

            struct RelationshipList: Codable {
                let data: [RelationshipItem]?
            }

            struct RelationshipItem: Codable {
                let id: String
                let type: String
            }

            struct IncludedItem: Codable {
                let id: String
                let type: String
                let attributes: [String: AnyCodable]?
            }

            struct Meta: Codable {
                let pagination: Pagination?
            }

            struct Pagination: Codable {
                let cursors: Cursors?
            }

            struct Cursors: Codable {
                let next: String?
            }
        }

        let response: StreamResponse = try await performRequest(request)

        // Build campaign lookup from included items
        var campaignLookup: [String: PatreonCampaign] = [:]
        var mediaLookup: [String: String] = [:]  // media ID -> download_url
        var mediaTypeLookup: [String: String] = [:]  // media ID -> media_type

        if let included = response.included {
            for item in included {
                if item.type == "campaign", let attrs = item.attributes {
                    let campaign = PatreonCampaign(
                        id: item.id,
                        name: (attrs["name"]?.value as? String) ?? "Unknown",
                        avatarURL: attrs["avatar_photo_url"]?.value as? String,
                        url: attrs["url"]?.value as? String
                    )
                    campaignLookup[item.id] = campaign
                }

                if item.type == "media", let attrs = item.attributes {
                    if let mediaType = attrs["media_type"]?.value as? String {
                        mediaTypeLookup[item.id] = mediaType
                    }
                    if let downloadURL = attrs["download_url"]?.value as? String {
                        mediaLookup[item.id] = downloadURL
                    }
                }
            }
        }

        // Convert to PatreonPost objects
        let posts = response.data.map { postData -> PatreonPost in
            let attrs = postData.attributes
            let dateFormatter = ISO8601DateFormatter()

            var campaign: PatreonCampaign?
            if let campaignId = postData.relationships?.campaign?.data?.id {
                campaign = campaignLookup[campaignId]
            }

            // Helper: check if a media item is actually a video (not an image thumbnail)
            func isVideoMedia(_ mediaId: String) -> Bool {
                if let mediaType = mediaTypeLookup[mediaId] {
                    // If media_type is known and is image, skip it
                    return !mediaType.hasPrefix("image/")
                }
                // media_type is nil/null — check if the download URL looks like an image
                if let url = mediaLookup[mediaId]?.lowercased() {
                    let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg"]
                    for ext in imageExtensions {
                        if url.contains(ext) { return false }
                    }
                }
                return true
            }

            // Try to find video URL from multiple relationship sources
            var videoURL: String?
            var audioURL: String?

            // 1. post_file relationship — only if it's actual video, not an image
            if let postFileId = postData.relationships?.postFile?.data?.id,
               isVideoMedia(postFileId) {
                videoURL = mediaLookup[postFileId]
            }

            // 2. media relationship (Patreon-hosted video) — filter out image thumbnails
            if videoURL == nil, let mediaRefs = postData.relationships?.media?.data {
                for ref in mediaRefs {
                    if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                        videoURL = url
                        break
                    }
                }
            }

            // 3. attachments_media — filter out image thumbnails
            if videoURL == nil, let attachmentRefs = postData.relationships?.attachmentsMedia?.data {
                for ref in attachmentRefs {
                    if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                        videoURL = url
                        break
                    }
                }
            }

            // 4. audio relationship
            if let audioId = postData.relationships?.audio?.data?.id {
                audioURL = mediaLookup[audioId]
            }

            // Extract embed URL: prefer embed_url attribute, fall back to parsing embed.html iframe
            var embedURL = attrs.embedUrl
            if embedURL == nil, let embedHtml = attrs.embed?.html {
                if let range = embedHtml.range(of: "src=\"", options: .caseInsensitive),
                   let endRange = embedHtml[range.upperBound...].range(of: "\"") {
                    embedURL = String(embedHtml[range.upperBound..<endRange.lowerBound])
                }
            }

            return PatreonPost(
                id: postData.id,
                title: attrs.title,
                content: attrs.content,
                teaser: attrs.teaser,
                publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
                url: attrs.url,
                embedURL: embedURL,
                imageURL: attrs.image?.url,
                thumbnailURL: attrs.thumbnailUrl ?? attrs.image?.thumbUrl,
                postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
                isPaid: attrs.isPaid ?? false,
                likeCount: attrs.likeCount ?? 0,
                commentCount: attrs.commentCount ?? 0,
                campaign: campaign,
                videoURL: videoURL,
                audioURL: audioURL
            )
        }

        let nextCursor = response.meta?.pagination?.cursors?.next

        return (posts, nextCursor)
    }

    // MARK: - Post Details

    /// Fetch a specific post with full details
    func fetchPost(id: String) async throws -> PatreonPost {
        let urlString = "\(apiBaseURL)/posts/\(id)?include=campaign,attachments_media,post_file,media,audio,images&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,embed,is_paid,like_count,comment_count,post_file&fields[campaign]=name,avatar_photo_url,url&fields[media]=download_url,image_urls,media_type,file_name,metadata"

        guard let url = URL(string: urlString) else {
            throw PatreonError.invalidURL
        }

        let request = createRequest(url: url)

        struct PostResponse: Codable {
            let data: PostData
            let included: [IncludedItem]?

            struct PostData: Codable {
                let id: String
                let attributes: PostAttributes
                let relationships: PostRelationships?
            }

            struct EmbedInfo: Codable {
                let html: String?
                let description: String?
                let url: String?
            }

            struct PostAttributes: Codable {
                let title: String?
                let content: String?
                let teaser: String?
                let publishedAt: String?
                let postType: String?
                let image: ImageData?
                let thumbnailUrl: String?
                let url: String?
                let embedUrl: String?
                let embed: EmbedInfo?
                let isPaid: Bool?
                let likeCount: Int?
                let commentCount: Int?

                enum CodingKeys: String, CodingKey {
                    case title, content, teaser
                    case publishedAt = "published_at"
                    case postType = "post_type"
                    case image
                    case thumbnailUrl = "thumbnail_url"
                    case url
                    case embedUrl = "embed_url"
                    case embed
                    case isPaid = "is_paid"
                    case likeCount = "like_count"
                    case commentCount = "comment_count"
                }
            }

            struct ImageData: Codable {
                let url: String?
            }

            struct PostRelationships: Codable {
                let campaign: RelationshipData?
                let postFile: RelationshipData?
                let attachmentsMedia: RelationshipList?
                let media: RelationshipList?
                let audio: RelationshipData?
                let images: RelationshipList?

                enum CodingKeys: String, CodingKey {
                    case campaign, media, audio, images
                    case postFile = "post_file"
                    case attachmentsMedia = "attachments_media"
                }
            }

            struct RelationshipData: Codable {
                let data: RelationshipItem?
            }

            struct RelationshipList: Codable {
                let data: [RelationshipItem]?
            }

            struct RelationshipItem: Codable {
                let id: String
                let type: String
            }

            struct IncludedItem: Codable {
                let id: String
                let type: String
                let attributes: [String: AnyCodable]?
            }
        }

        let response: PostResponse = try await performRequest(request)

        let attrs = response.data.attributes
        let dateFormatter = ISO8601DateFormatter()

        // Build campaign and media lookups from included items
        var campaign: PatreonCampaign?
        var mediaLookup: [String: String] = [:]  // media ID -> download_url
        var mediaTypeLookup: [String: String] = [:]  // media ID -> media_type

        if let included = response.included {
            for item in included {
                if item.type == "campaign" {
                    if let campaignId = response.data.relationships?.campaign?.data?.id,
                       item.id == campaignId,
                       let itemAttrs = item.attributes {
                        campaign = PatreonCampaign(
                            id: item.id,
                            name: (itemAttrs["name"]?.value as? String) ?? "Unknown",
                            avatarURL: itemAttrs["avatar_photo_url"]?.value as? String,
                            url: itemAttrs["url"]?.value as? String
                        )
                    }
                }

                if item.type == "media", let itemAttrs = item.attributes {
                    if let mediaType = itemAttrs["media_type"]?.value as? String {
                        mediaTypeLookup[item.id] = mediaType
                        print("[PatreonAPI] Media \(item.id) type: \(mediaType)")
                    }
                    if let downloadURL = itemAttrs["download_url"]?.value as? String {
                        mediaLookup[item.id] = downloadURL
                        print("[PatreonAPI] Found media \(item.id): \(downloadURL.prefix(80))...")
                    }
                }
            }
        }

        // Helper: check if a media item is actually a video (not an image thumbnail)
        func isVideoMedia(_ mediaId: String) -> Bool {
            if let mediaType = mediaTypeLookup[mediaId] {
                return !mediaType.hasPrefix("image/")
            }
            // media_type is nil/null — check if the download URL looks like an image
            if let url = mediaLookup[mediaId]?.lowercased() {
                let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg"]
                for ext in imageExtensions {
                    if url.contains(ext) { return false }
                }
            }
            return true
        }

        // Extract video URL from multiple relationship sources
        var videoURL: String?
        var audioURL: String?

        // 1. post_file relationship — only if it's actual video, not an image
        if let postFileId = response.data.relationships?.postFile?.data?.id {
            if isVideoMedia(postFileId) {
                videoURL = mediaLookup[postFileId]
            }
            print("[PatreonAPI] Post file ID: \(postFileId), isVideo: \(isVideoMedia(postFileId)), URL: \(mediaLookup[postFileId] ?? "nil")")
        }

        // 2. media relationship (Patreon-hosted video) — filter out image thumbnails
        if videoURL == nil, let mediaRefs = response.data.relationships?.media?.data {
            for ref in mediaRefs {
                if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                    videoURL = url
                    print("[PatreonAPI] Found video in media rel \(ref.id): \(url.prefix(80))...")
                    break
                } else {
                    print("[PatreonAPI] Skipping image-only media \(ref.id) (type: \(mediaTypeLookup[ref.id] ?? "nil"))")
                }
            }
        }

        // 3. attachments_media — filter out image thumbnails
        if videoURL == nil, let attachmentRefs = response.data.relationships?.attachmentsMedia?.data {
            for ref in attachmentRefs {
                if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                    videoURL = url
                    print("[PatreonAPI] Found video in attachment \(ref.id): \(url.prefix(80))...")
                    break
                }
            }
        }

        // 4. audio relationship
        if let audioId = response.data.relationships?.audio?.data?.id {
            audioURL = mediaLookup[audioId]
            print("[PatreonAPI] Audio ID: \(audioId), URL: \(audioURL ?? "nil")")
        }

        // Extract embed URL: prefer embed_url attribute, fall back to parsing embed.html iframe
        var embedURL = attrs.embedUrl
        if embedURL == nil, let embedHtml = attrs.embed?.html {
            if let range = embedHtml.range(of: "src=\"", options: .caseInsensitive),
               let endRange = embedHtml[range.upperBound...].range(of: "\"") {
                embedURL = String(embedHtml[range.upperBound..<endRange.lowerBound])
            }
        }

        print("[PatreonAPI] fetchPost(\(id)) - postType: \(attrs.postType ?? "nil"), embedURL: \(embedURL ?? "nil"), videoURL: \(videoURL ?? "nil"), audioURL: \(audioURL ?? "nil"), mediaCount: \(mediaLookup.count)")

        return PatreonPost(
            id: response.data.id,
            title: attrs.title,
            content: attrs.content,
            teaser: attrs.teaser,
            publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
            url: attrs.url,
            embedURL: embedURL,
            imageURL: attrs.image?.url,
            thumbnailURL: attrs.thumbnailUrl,
            postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
            isPaid: attrs.isPaid ?? false,
            likeCount: attrs.likeCount ?? 0,
            commentCount: attrs.commentCount ?? 0,
            campaign: campaign,
            videoURL: videoURL,
            audioURL: audioURL
        )
    }

    // MARK: - Campaign/Creator Endpoints

    /// Fetch campaigns the user is a member of (creators they support)
    func fetchMemberships() async throws -> [PatreonCampaign] {
        let urlString = "\(apiBaseURL)/current_user/memberships?include=campaign&fields[campaign]=name,avatar_photo_url,cover_photo_url,summary,creation_name,patron_count,url&fields[member]=patron_status"

        guard let url = URL(string: urlString) else {
            throw PatreonError.invalidURL
        }

        let request = createRequest(url: url)

        struct MembershipsResponse: Codable {
            let data: [MembershipData]
            let included: [IncludedItem]?

            struct MembershipData: Codable {
                let id: String
                let relationships: MembershipRelationships?
            }

            struct MembershipRelationships: Codable {
                let campaign: RelationshipData?
            }

            struct RelationshipData: Codable {
                let data: RelationshipItem?
            }

            struct RelationshipItem: Codable {
                let id: String
                let type: String
            }

            struct IncludedItem: Codable {
                let id: String
                let type: String
                let attributes: [String: AnyCodable]?
            }
        }

        let response: MembershipsResponse = try await performRequest(request)

        // Build campaigns from included items
        var campaigns: [PatreonCampaign] = []
        if let included = response.included {
            for item in included where item.type == "campaign" {
                if let attrs = item.attributes {
                    let campaign = PatreonCampaign(
                        id: item.id,
                        name: (attrs["name"]?.value as? String) ?? "Unknown",
                        summary: attrs["summary"]?.value as? String,
                        creationName: attrs["creation_name"]?.value as? String,
                        avatarURL: attrs["avatar_photo_url"]?.value as? String,
                        coverPhotoURL: attrs["cover_photo_url"]?.value as? String,
                        patronCount: attrs["patron_count"]?.value as? Int,
                        url: attrs["url"]?.value as? String
                    )
                    campaigns.append(campaign)
                }
            }
        }

        return campaigns
    }

    /// Fetch posts from a specific campaign/creator
    func fetchCampaignPosts(campaignId: String, cursor: String? = nil, limit: Int = 20) async throws -> (posts: [PatreonPost], nextCursor: String?) {
        var urlString = "\(apiBaseURL)/campaigns/\(campaignId)/posts?include=attachments_media,post_file,media,audio,images&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,embed,is_paid,like_count,comment_count,post_file&fields[media]=download_url,image_urls,media_type,file_name,metadata&page[count]=\(limit)"

        if let cursor = cursor {
            urlString += "&page[cursor]=\(cursor)"
        }

        guard let url = URL(string: urlString) else {
            throw PatreonError.invalidURL
        }

        let request = createRequest(url: url)

        struct PostsResponse: Codable {
            let data: [PostData]
            let included: [IncludedItem]?
            let meta: Meta?

            struct PostData: Codable {
                let id: String
                let attributes: PostAttributes
                let relationships: PostRelationships?
            }

            struct EmbedInfo: Codable {
                let html: String?
                let description: String?
                let url: String?
            }

            struct PostAttributes: Codable {
                let title: String?
                let content: String?
                let teaser: String?
                let publishedAt: String?
                let postType: String?
                let image: ImageData?
                let thumbnailUrl: String?
                let url: String?
                let embedUrl: String?
                let embed: EmbedInfo?
                let isPaid: Bool?
                let likeCount: Int?
                let commentCount: Int?

                enum CodingKeys: String, CodingKey {
                    case title, content, teaser
                    case publishedAt = "published_at"
                    case postType = "post_type"
                    case image
                    case thumbnailUrl = "thumbnail_url"
                    case url
                    case embedUrl = "embed_url"
                    case embed
                    case isPaid = "is_paid"
                    case likeCount = "like_count"
                    case commentCount = "comment_count"
                }
            }

            struct ImageData: Codable {
                let url: String?
            }

            struct PostRelationships: Codable {
                let postFile: RelationshipData?
                let attachmentsMedia: RelationshipList?
                let media: RelationshipList?
                let audio: RelationshipData?
                let images: RelationshipList?

                enum CodingKeys: String, CodingKey {
                    case media, audio, images
                    case postFile = "post_file"
                    case attachmentsMedia = "attachments_media"
                }
            }

            struct RelationshipData: Codable {
                let data: RelationshipItem?
            }

            struct RelationshipList: Codable {
                let data: [RelationshipItem]?
            }

            struct RelationshipItem: Codable {
                let id: String
                let type: String
            }

            struct IncludedItem: Codable {
                let id: String
                let type: String
                let attributes: [String: AnyCodable]?
            }

            struct Meta: Codable {
                let pagination: Pagination?
            }

            struct Pagination: Codable {
                let cursors: Cursors?
            }

            struct Cursors: Codable {
                let next: String?
            }
        }

        let response: PostsResponse = try await performRequest(request)
        let dateFormatter = ISO8601DateFormatter()

        // Build media lookup from included items
        var mediaLookup: [String: String] = [:]
        var mediaTypeLookup: [String: String] = [:]
        if let included = response.included {
            for item in included where item.type == "media" {
                if let attrs = item.attributes {
                    if let mediaType = attrs["media_type"]?.value as? String {
                        mediaTypeLookup[item.id] = mediaType
                    }
                    if let downloadURL = attrs["download_url"]?.value as? String {
                        mediaLookup[item.id] = downloadURL
                    }
                }
            }
        }

        let posts = response.data.map { postData -> PatreonPost in
            let attrs = postData.attributes

            // Helper: check if a media item is actually a video (not an image thumbnail)
            func isVideoMedia(_ mediaId: String) -> Bool {
                if let mediaType = mediaTypeLookup[mediaId] {
                    return !mediaType.hasPrefix("image/")
                }
                if let url = mediaLookup[mediaId]?.lowercased() {
                    let imageExtensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp", ".svg"]
                    for ext in imageExtensions {
                        if url.contains(ext) { return false }
                    }
                }
                return true
            }

            // Extract video/audio URL from all relationship sources
            var videoURL: String?
            var audioURL: String?

            // 1. post_file relationship — only if it's actual video
            if let postFileId = postData.relationships?.postFile?.data?.id,
               isVideoMedia(postFileId) {
                videoURL = mediaLookup[postFileId]
            }

            // 2. media relationship (Patreon-hosted video) — filter out image thumbnails
            if videoURL == nil, let mediaRefs = postData.relationships?.media?.data {
                for ref in mediaRefs {
                    if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                        videoURL = url
                        break
                    }
                }
            }

            // 3. attachments_media — filter out image thumbnails
            if videoURL == nil, let attachmentRefs = postData.relationships?.attachmentsMedia?.data {
                for ref in attachmentRefs {
                    if isVideoMedia(ref.id), let url = mediaLookup[ref.id] {
                        videoURL = url
                        break
                    }
                }
            }

            // 4. audio relationship
            if let audioId = postData.relationships?.audio?.data?.id {
                audioURL = mediaLookup[audioId]
            }

            // Extract embed URL: prefer embed_url attribute, fall back to parsing embed.html iframe
            var embedURL = attrs.embedUrl
            if embedURL == nil, let embedHtml = attrs.embed?.html {
                if let range = embedHtml.range(of: "src=\"", options: .caseInsensitive),
                   let endRange = embedHtml[range.upperBound...].range(of: "\"") {
                    embedURL = String(embedHtml[range.upperBound..<endRange.lowerBound])
                }
            }

            return PatreonPost(
                id: postData.id,
                title: attrs.title,
                content: attrs.content,
                teaser: attrs.teaser,
                publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
                url: attrs.url,
                embedURL: embedURL,
                imageURL: attrs.image?.url,
                thumbnailURL: attrs.thumbnailUrl,
                postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
                isPaid: attrs.isPaid ?? false,
                likeCount: attrs.likeCount ?? 0,
                commentCount: attrs.commentCount ?? 0,
                videoURL: videoURL,
                audioURL: audioURL
            )
        }

        return (posts, response.meta?.pagination?.cursors?.next)
    }
}

// MARK: - Errors

enum PatreonError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case invalidURL
    case httpError(Int)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated. Please log in to Patreon."
        case .invalidResponse:
            return "Invalid response from Patreon."
        case .invalidURL:
            return "Invalid URL."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}
