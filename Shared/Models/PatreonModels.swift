//
//  PatreonModels.swift
//  PatreonTV
//
//  Shared data models for Patreon content
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import Foundation

// MARK: - Patreon User

/// Represents the authenticated Patreon user
struct PatreonUser: Codable, Identifiable {
    let id: String
    let fullName: String
    let email: String?
    let imageURL: String?
    let thumbURL: String?
    let isCreator: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case email
        case imageURL = "image_url"
        case thumbURL = "thumb_url"
        case isCreator = "is_creator"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName) ?? "Unknown"
        email = try container.decodeIfPresent(String.self, forKey: .email)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        thumbURL = try container.decodeIfPresent(String.self, forKey: .thumbURL)
        isCreator = try container.decodeIfPresent(Bool.self, forKey: .isCreator) ?? false
    }

    init(id: String, fullName: String, email: String? = nil, imageURL: String? = nil, thumbURL: String? = nil, isCreator: Bool = false) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.imageURL = imageURL
        self.thumbURL = thumbURL
        self.isCreator = isCreator
    }
}

// MARK: - Patreon Creator/Campaign

/// Represents a Patreon creator's campaign
struct PatreonCampaign: Codable, Identifiable {
    let id: String
    let name: String
    let summary: String?
    let creationName: String?
    let imageURL: String?
    let avatarURL: String?
    let coverPhotoURL: String?
    let patronCount: Int?
    let url: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case summary
        case creationName = "creation_name"
        case imageURL = "image_url"
        case avatarURL = "avatar_photo_url"
        case coverPhotoURL = "cover_photo_url"
        case patronCount = "patron_count"
        case url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Creator"
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        creationName = try container.decodeIfPresent(String.self, forKey: .creationName)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        avatarURL = try container.decodeIfPresent(String.self, forKey: .avatarURL)
        coverPhotoURL = try container.decodeIfPresent(String.self, forKey: .coverPhotoURL)
        patronCount = try container.decodeIfPresent(Int.self, forKey: .patronCount)
        url = try container.decodeIfPresent(String.self, forKey: .url)
    }

    init(id: String, name: String, summary: String? = nil, creationName: String? = nil,
         imageURL: String? = nil, avatarURL: String? = nil, coverPhotoURL: String? = nil,
         patronCount: Int? = nil, url: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.creationName = creationName
        self.imageURL = imageURL
        self.avatarURL = avatarURL
        self.coverPhotoURL = coverPhotoURL
        self.patronCount = patronCount
        self.url = url
    }
}

// MARK: - Patreon Post

/// Represents a post from a Patreon creator
struct PatreonPost: Codable, Identifiable {
    let id: String
    let title: String?
    let content: String?
    let teaser: String?
    let publishedAt: Date?
    let editedAt: Date?
    let url: String?
    let embedURL: String?
    let imageURL: String?
    let thumbnailURL: String?
    let postType: PostType
    let isPaid: Bool
    let isPublic: Bool
    let likeCount: Int
    let commentCount: Int

    // Associated campaign/creator
    var campaign: PatreonCampaign?

    // Media attachments
    var attachments: [PatreonAttachment]?
    var videoURL: String?
    var audioURL: String?

    enum PostType: String, Codable {
        case text = "text_only"
        case image = "image_file"
        case video = "video_embed"
        case videoFile = "video_external_file"
        case audio = "audio_file"
        case audioEmbed = "audio_embed"
        case link = "link"
        case poll = "poll"
        case livestream = "livestream"
        case livestreamYoutube = "livestream_youtube"
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = PostType(rawValue: value) ?? .unknown
        }

        /// Whether this type represents video content
        var isVideoType: Bool {
            self == .video || self == .videoFile || self == .livestream || self == .livestreamYoutube
        }

        /// Whether this type represents audio content
        var isAudioType: Bool {
            self == .audio || self == .audioEmbed
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case content
        case teaser
        case publishedAt = "published_at"
        case editedAt = "edited_at"
        case url
        case embedURL = "embed_url"
        case imageURL = "image"
        case thumbnailURL = "thumbnail_url"
        case postType = "post_type"
        case isPaid = "is_paid"
        case isPublic = "is_public"
        case likeCount = "like_count"
        case commentCount = "comment_count"
        case campaign
        case attachments
        case videoURL = "video_url"
        case audioURL = "audio_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        teaser = try container.decodeIfPresent(String.self, forKey: .teaser)
        url = try container.decodeIfPresent(String.self, forKey: .url)
        embedURL = try container.decodeIfPresent(String.self, forKey: .embedURL)
        imageURL = try container.decodeIfPresent(String.self, forKey: .imageURL)
        thumbnailURL = try container.decodeIfPresent(String.self, forKey: .thumbnailURL)
        postType = try container.decodeIfPresent(PostType.self, forKey: .postType) ?? .unknown
        isPaid = try container.decodeIfPresent(Bool.self, forKey: .isPaid) ?? false
        isPublic = try container.decodeIfPresent(Bool.self, forKey: .isPublic) ?? false
        likeCount = try container.decodeIfPresent(Int.self, forKey: .likeCount) ?? 0
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        campaign = try container.decodeIfPresent(PatreonCampaign.self, forKey: .campaign)
        attachments = try container.decodeIfPresent([PatreonAttachment].self, forKey: .attachments)
        videoURL = try container.decodeIfPresent(String.self, forKey: .videoURL)
        audioURL = try container.decodeIfPresent(String.self, forKey: .audioURL)

        // Parse dates
        if let dateString = try container.decodeIfPresent(String.self, forKey: .publishedAt) {
            publishedAt = ISO8601DateFormatter().date(from: dateString)
        } else {
            publishedAt = nil
        }

        if let dateString = try container.decodeIfPresent(String.self, forKey: .editedAt) {
            editedAt = ISO8601DateFormatter().date(from: dateString)
        } else {
            editedAt = nil
        }
    }

    init(id: String, title: String?, content: String? = nil, teaser: String? = nil,
         publishedAt: Date? = nil, editedAt: Date? = nil, url: String? = nil,
         embedURL: String? = nil, imageURL: String? = nil, thumbnailURL: String? = nil,
         postType: PostType = .text, isPaid: Bool = false, isPublic: Bool = false,
         likeCount: Int = 0, commentCount: Int = 0, campaign: PatreonCampaign? = nil,
         attachments: [PatreonAttachment]? = nil, videoURL: String? = nil, audioURL: String? = nil) {
        self.id = id
        self.title = title
        self.content = content
        self.teaser = teaser
        self.publishedAt = publishedAt
        self.editedAt = editedAt
        self.url = url
        self.embedURL = embedURL
        self.imageURL = imageURL
        self.thumbnailURL = thumbnailURL
        self.postType = postType
        self.isPaid = isPaid
        self.isPublic = isPublic
        self.likeCount = likeCount
        self.commentCount = commentCount
        self.campaign = campaign
        self.attachments = attachments
        self.videoURL = videoURL
        self.audioURL = audioURL
    }

    /// Display title (falls back to post type if no title)
    var displayTitle: String {
        if let title = title, !title.isEmpty {
            return title
        }
        switch postType {
        case .video, .livestreamYoutube: return "Video Post"
        case .videoFile: return "Video Post"
        case .livestream: return "Livestream"
        case .audio: return "Audio Post"
        case .image: return "Image Post"
        case .link: return "Link Post"
        case .poll: return "Poll"
        default: return "Post"
        }
    }

    /// Preview text for the post
    var previewText: String? {
        if let teaser = teaser, !teaser.isEmpty {
            return teaser
        }
        if let content = content {
            // Strip HTML and truncate
            let stripped = content.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            if stripped.count > 200 {
                return String(stripped.prefix(200)) + "..."
            }
            return stripped
        }
        return nil
    }

    /// Check if post has playable media
    var hasVideo: Bool {
        videoURL != nil || embedURL != nil || postType.isVideoType
    }

    var hasAudio: Bool {
        audioURL != nil || postType.isAudioType
    }
}

// MARK: - Patreon Attachment

/// Represents a media attachment on a post
struct PatreonAttachment: Codable, Identifiable {
    let id: String
    let name: String?
    let url: String?
    let mediaType: String?
    let size: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case url
        case mediaType = "media_type"
        case size
    }

    var isImage: Bool {
        mediaType?.hasPrefix("image/") ?? false
    }

    var isVideo: Bool {
        mediaType?.hasPrefix("video/") ?? false
    }

    var isAudio: Bool {
        mediaType?.hasPrefix("audio/") ?? false
    }
}

// MARK: - Pairing Session

/// Represents a pairing session between Apple TV and the relay server
struct PairingSession: Codable, Identifiable {
    let id: String           // Unique session ID
    let code: String         // 6-character pairing code displayed on TV
    let createdAt: Date
    var expiresAt: Date
    var status: PairingStatus
    var sessionToken: String?  // Patreon session token once authenticated
    var userInfo: PatreonUser?

    enum PairingStatus: String, Codable {
        case pending    // Waiting for user to scan QR
        case scanning   // User scanned, loading login page
        case authenticating  // User is logging in
        case completed  // Successfully authenticated
        case expired    // Session timed out
        case failed     // Authentication failed
    }

    init(id: String = UUID().uuidString, code: String, expiresIn: TimeInterval = 300) {
        self.id = id
        self.code = code
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(expiresIn)
        self.status = .pending
        self.sessionToken = nil
        self.userInfo = nil
    }

    var isExpired: Bool {
        Date() > expiresAt
    }

    /// Generate a random 6-character pairing code
    static func generateCode() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789" // Removed confusing chars like 0/O, 1/I
        return String((0..<6).map { _ in characters.randomElement()! })
    }
}

// MARK: - API Response Wrappers

/// Wrapper for Patreon API responses
struct PatreonAPIResponse<T: Codable>: Codable {
    let data: T?
    let included: [PatreonIncludedItem]?
    let meta: PatreonMeta?
    let links: PatreonLinks?
}

struct PatreonIncludedItem: Codable {
    let id: String
    let type: String
    let attributes: [String: AnyCodable]?
}

struct PatreonMeta: Codable {
    let pagination: PatreonPagination?
}

struct PatreonPagination: Codable {
    let cursors: PatreonCursors?
    let total: Int?
}

struct PatreonCursors: Codable {
    let next: String?
}

struct PatreonLinks: Codable {
    let next: String?
}

// MARK: - Helper for Any Codable

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
