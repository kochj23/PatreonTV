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
        var urlString = "\(apiBaseURL)/stream?include=user,campaign,attachments_media,post_file&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,is_paid,like_count,comment_count,post_file&fields[campaign]=name,avatar_photo_url,url&fields[media]=download_url,image_urls,media_type,file_name&page[count]=\(limit)"

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

                enum CodingKeys: String, CodingKey {
                    case campaign, user
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

            // Try to find video URL from post_file relationship
            var videoURL: String?
            if let postFileId = postData.relationships?.postFile?.data?.id {
                videoURL = mediaLookup[postFileId]
            }

            // Also check attachments_media for video URLs
            if videoURL == nil, let attachmentRefs = postData.relationships?.attachmentsMedia?.data {
                for ref in attachmentRefs {
                    if let url = mediaLookup[ref.id] {
                        videoURL = url
                        break
                    }
                }
            }

            return PatreonPost(
                id: postData.id,
                title: attrs.title,
                content: attrs.content,
                teaser: attrs.teaser,
                publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
                url: attrs.url,
                embedURL: attrs.embedUrl,
                imageURL: attrs.image?.url,
                thumbnailURL: attrs.thumbnailUrl ?? attrs.image?.thumbUrl,
                postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
                isPaid: attrs.isPaid ?? false,
                likeCount: attrs.likeCount ?? 0,
                commentCount: attrs.commentCount ?? 0,
                campaign: campaign,
                videoURL: videoURL
            )
        }

        let nextCursor = response.meta?.pagination?.cursors?.next

        return (posts, nextCursor)
    }

    // MARK: - Post Details

    /// Fetch a specific post with full details
    func fetchPost(id: String) async throws -> PatreonPost {
        let urlString = "\(apiBaseURL)/posts/\(id)?include=campaign,attachments_media&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,is_paid,like_count,comment_count&fields[campaign]=name,avatar_photo_url,url"

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

        let response: PostResponse = try await performRequest(request)

        let attrs = response.data.attributes
        let dateFormatter = ISO8601DateFormatter()

        // Find campaign in included
        var campaign: PatreonCampaign?
        if let campaignId = response.data.relationships?.campaign?.data?.id,
           let included = response.included {
            for item in included where item.type == "campaign" && item.id == campaignId {
                if let attrs = item.attributes {
                    campaign = PatreonCampaign(
                        id: item.id,
                        name: (attrs["name"]?.value as? String) ?? "Unknown",
                        avatarURL: attrs["avatar_photo_url"]?.value as? String,
                        url: attrs["url"]?.value as? String
                    )
                }
            }
        }

        return PatreonPost(
            id: response.data.id,
            title: attrs.title,
            content: attrs.content,
            teaser: attrs.teaser,
            publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
            url: attrs.url,
            embedURL: attrs.embedUrl,
            imageURL: attrs.image?.url,
            thumbnailURL: attrs.thumbnailUrl,
            postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
            isPaid: attrs.isPaid ?? false,
            likeCount: attrs.likeCount ?? 0,
            commentCount: attrs.commentCount ?? 0,
            campaign: campaign
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
        var urlString = "\(apiBaseURL)/campaigns/\(campaignId)/posts?include=attachments_media&fields[post]=title,content,teaser,published_at,post_type,image,thumbnail_url,url,embed_url,is_paid,like_count,comment_count&page[count]=\(limit)"

        if let cursor = cursor {
            urlString += "&page[cursor]=\(cursor)"
        }

        guard let url = URL(string: urlString) else {
            throw PatreonError.invalidURL
        }

        let request = createRequest(url: url)

        // Response structure is similar to fetchHomeFeed
        // Reusing the same logic would be cleaner but keeping it explicit for now
        struct PostsResponse: Codable {
            let data: [PostData]
            let meta: Meta?

            struct PostData: Codable {
                let id: String
                let attributes: PostAttributes
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
                    case isPaid = "is_paid"
                    case likeCount = "like_count"
                    case commentCount = "comment_count"
                }
            }

            struct ImageData: Codable {
                let url: String?
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

        let posts = response.data.map { postData -> PatreonPost in
            let attrs = postData.attributes

            return PatreonPost(
                id: postData.id,
                title: attrs.title,
                content: attrs.content,
                teaser: attrs.teaser,
                publishedAt: attrs.publishedAt.flatMap { dateFormatter.date(from: $0) },
                url: attrs.url,
                embedURL: attrs.embedUrl,
                imageURL: attrs.image?.url,
                thumbnailURL: attrs.thumbnailUrl,
                postType: PatreonPost.PostType(rawValue: attrs.postType ?? "") ?? .unknown,
                isPaid: attrs.isPaid ?? false,
                likeCount: attrs.likeCount ?? 0,
                commentCount: attrs.commentCount ?? 0
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
