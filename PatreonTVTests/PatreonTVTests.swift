//
//  PatreonTVTests.swift
//  PatreonTVTests
//
//  Unit tests for PatreonTV data models, parsing, and security
//  Created by Jordan Koch
//  Copyright 2026 Jordan Koch. All rights reserved.
//

import XCTest
@testable import PatreonTV

// MARK: - PatreonUser Tests

final class PatreonUserTests: XCTestCase {

    func testUserInitialization() {
        let user = PatreonUser(id: "123", fullName: "Test User", email: "test@example.com", isCreator: true)
        XCTAssertEqual(user.id, "123")
        XCTAssertEqual(user.fullName, "Test User")
        XCTAssertEqual(user.email, "test@example.com")
        XCTAssertTrue(user.isCreator)
    }

    func testUserDecoding() throws {
        let json = """
        {
            "id": "456",
            "full_name": "Jordan Koch",
            "email": "user@example.com",
            "image_url": "https://example.com/avatar.jpg",
            "thumb_url": "https://example.com/thumb.jpg",
            "is_creator": false
        }
        """
        let data = json.data(using: .utf8)!
        let user = try JSONDecoder().decode(PatreonUser.self, from: data)

        XCTAssertEqual(user.id, "456")
        XCTAssertEqual(user.fullName, "Jordan Koch")
        XCTAssertEqual(user.email, "user@example.com")
        XCTAssertEqual(user.imageURL, "https://example.com/avatar.jpg")
        XCTAssertFalse(user.isCreator)
    }

    func testUserDecodingWithMissingFields() throws {
        let json = """
        {
            "id": "789"
        }
        """
        let data = json.data(using: .utf8)!
        let user = try JSONDecoder().decode(PatreonUser.self, from: data)

        XCTAssertEqual(user.id, "789")
        XCTAssertEqual(user.fullName, "Unknown")
        XCTAssertNil(user.email)
        XCTAssertNil(user.imageURL)
        XCTAssertFalse(user.isCreator)
    }
}

// MARK: - PatreonCampaign Tests

final class PatreonCampaignTests: XCTestCase {

    func testCampaignInitialization() {
        let campaign = PatreonCampaign(
            id: "camp1",
            name: "Test Campaign",
            summary: "A test campaign",
            patronCount: 100
        )
        XCTAssertEqual(campaign.id, "camp1")
        XCTAssertEqual(campaign.name, "Test Campaign")
        XCTAssertEqual(campaign.patronCount, 100)
    }

    func testCampaignDecodingWithMissingName() throws {
        let json = """
        {
            "id": "camp2"
        }
        """
        let data = json.data(using: .utf8)!
        let campaign = try JSONDecoder().decode(PatreonCampaign.self, from: data)
        XCTAssertEqual(campaign.name, "Unknown Creator")
    }

    func testCampaignDecoding() throws {
        let json = """
        {
            "id": "camp3",
            "name": "Creator Channel",
            "summary": "Great content",
            "creation_name": "videos",
            "image_url": "https://example.com/img.jpg",
            "avatar_photo_url": "https://example.com/avatar.jpg",
            "patron_count": 500
        }
        """
        let data = json.data(using: .utf8)!
        let campaign = try JSONDecoder().decode(PatreonCampaign.self, from: data)

        XCTAssertEqual(campaign.id, "camp3")
        XCTAssertEqual(campaign.name, "Creator Channel")
        XCTAssertEqual(campaign.creationName, "videos")
        XCTAssertEqual(campaign.patronCount, 500)
        XCTAssertNotNil(campaign.avatarURL)
    }
}

// MARK: - PatreonPost Tests

final class PatreonPostTests: XCTestCase {

    func testPostInitialization() {
        let post = PatreonPost(
            id: "post1",
            title: "Test Post",
            content: "<p>Hello world</p>",
            postType: .text,
            isPaid: true,
            isPublic: false,
            likeCount: 42,
            commentCount: 7
        )
        XCTAssertEqual(post.id, "post1")
        XCTAssertEqual(post.title, "Test Post")
        XCTAssertTrue(post.isPaid)
        XCTAssertFalse(post.isPublic)
        XCTAssertEqual(post.likeCount, 42)
    }

    func testPostDisplayTitle() {
        let textPost = PatreonPost(id: "1", title: nil, postType: .text)
        XCTAssertEqual(textPost.displayTitle, "Post")

        let videoPost = PatreonPost(id: "2", title: nil, postType: .video)
        XCTAssertEqual(videoPost.displayTitle, "Video Post")

        let audioPost = PatreonPost(id: "3", title: nil, postType: .audio)
        XCTAssertEqual(audioPost.displayTitle, "Audio Post")

        let imagePost = PatreonPost(id: "4", title: nil, postType: .image)
        XCTAssertEqual(imagePost.displayTitle, "Image Post")

        let livestream = PatreonPost(id: "5", title: nil, postType: .livestream)
        XCTAssertEqual(livestream.displayTitle, "Livestream")

        let titled = PatreonPost(id: "6", title: "My Great Post", postType: .text)
        XCTAssertEqual(titled.displayTitle, "My Great Post")

        let emptyTitle = PatreonPost(id: "7", title: "", postType: .video)
        XCTAssertEqual(emptyTitle.displayTitle, "Video Post")
    }

    func testPostPreviewText() {
        let postWithTeaser = PatreonPost(id: "1", title: "Test", teaser: "Short teaser", postType: .text)
        XCTAssertEqual(postWithTeaser.previewText, "Short teaser")

        let postWithHTML = PatreonPost(id: "2", title: "Test", content: "<p>Hello <b>world</b></p>", postType: .text)
        XCTAssertEqual(postWithHTML.previewText, "Hello world")

        let longContent = String(repeating: "A", count: 300)
        let postWithLongContent = PatreonPost(id: "3", title: "Test", content: longContent, postType: .text)
        XCTAssertTrue(postWithLongContent.previewText!.count <= 203) // 200 + "..."

        let postNoContent = PatreonPost(id: "4", title: "Test", postType: .text)
        XCTAssertNil(postNoContent.previewText)
    }

    func testPostMediaDetection() {
        let videoPost = PatreonPost(id: "1", title: "Video", postType: .video, videoURL: "https://example.com/video.mp4")
        XCTAssertTrue(videoPost.hasVideo)

        let embedPost = PatreonPost(id: "2", title: "Embed", embedURL: "https://youtube.com/watch?v=123", postType: .text)
        XCTAssertTrue(embedPost.hasVideo)

        let audioPost = PatreonPost(id: "3", title: "Audio", postType: .audio, audioURL: "https://example.com/audio.mp3")
        XCTAssertTrue(audioPost.hasAudio)

        let textPost = PatreonPost(id: "4", title: "Text", postType: .text)
        XCTAssertFalse(textPost.hasVideo)
        XCTAssertFalse(textPost.hasAudio)
    }

    func testPostTypeVideoDetection() {
        XCTAssertTrue(PatreonPost.PostType.video.isVideoType)
        XCTAssertTrue(PatreonPost.PostType.videoFile.isVideoType)
        XCTAssertTrue(PatreonPost.PostType.livestream.isVideoType)
        XCTAssertTrue(PatreonPost.PostType.livestreamYoutube.isVideoType)
        XCTAssertFalse(PatreonPost.PostType.text.isVideoType)
        XCTAssertFalse(PatreonPost.PostType.audio.isVideoType)
    }

    func testPostTypeAudioDetection() {
        XCTAssertTrue(PatreonPost.PostType.audio.isAudioType)
        XCTAssertTrue(PatreonPost.PostType.audioEmbed.isAudioType)
        XCTAssertFalse(PatreonPost.PostType.video.isAudioType)
        XCTAssertFalse(PatreonPost.PostType.text.isAudioType)
    }

    func testPostTypeUnknownFallback() throws {
        let json = """
        {
            "id": "1",
            "post_type": "something_new"
        }
        """
        let data = json.data(using: .utf8)!
        let post = try JSONDecoder().decode(PatreonPost.self, from: data)
        XCTAssertEqual(post.postType, .unknown)
    }
}

// MARK: - PatreonAttachment Tests

final class PatreonAttachmentTests: XCTestCase {

    func testAttachmentMediaTypeDetection() throws {
        let json = """
        {"id": "1", "name": "photo.jpg", "media_type": "image/jpeg", "size": 1024}
        """
        let data = json.data(using: .utf8)!
        let attachment = try JSONDecoder().decode(PatreonAttachment.self, from: data)

        XCTAssertTrue(attachment.isImage)
        XCTAssertFalse(attachment.isVideo)
        XCTAssertFalse(attachment.isAudio)
    }

    func testVideoAttachment() throws {
        let json = """
        {"id": "2", "name": "video.mp4", "media_type": "video/mp4"}
        """
        let data = json.data(using: .utf8)!
        let attachment = try JSONDecoder().decode(PatreonAttachment.self, from: data)

        XCTAssertTrue(attachment.isVideo)
        XCTAssertFalse(attachment.isImage)
    }

    func testAudioAttachment() throws {
        let json = """
        {"id": "3", "name": "podcast.mp3", "media_type": "audio/mpeg"}
        """
        let data = json.data(using: .utf8)!
        let attachment = try JSONDecoder().decode(PatreonAttachment.self, from: data)

        XCTAssertTrue(attachment.isAudio)
        XCTAssertFalse(attachment.isImage)
    }

    func testNilMediaType() {
        // When media_type is nil, all type checks should return false
        let attachment = PatreonAttachment(id: "4", name: "file.dat", url: nil, mediaType: nil, size: nil)
        XCTAssertFalse(attachment.isImage)
        XCTAssertFalse(attachment.isVideo)
        XCTAssertFalse(attachment.isAudio)
    }
}

// MARK: - PairingSession Tests

final class PairingSessionTests: XCTestCase {

    func testCodeGeneration() {
        let code = PairingSession.generateCode()
        XCTAssertEqual(code.count, 6)

        // Verify no confusing characters
        let confusing: Set<Character> = ["0", "O", "1", "I"]
        for char in code {
            XCTAssertFalse(confusing.contains(char), "Code should not contain confusing character: \(char)")
        }
    }

    func testCodeGenerationUniqueness() {
        var codes = Set<String>()
        for _ in 0..<100 {
            codes.insert(PairingSession.generateCode())
        }
        // Not all 100 should be the same (probabilistically impossible)
        XCTAssertGreaterThan(codes.count, 1)
    }

    func testSessionExpiry() {
        let session = PairingSession(code: "ABC123", expiresIn: -1) // Already expired
        XCTAssertTrue(session.isExpired)
    }

    func testSessionNotExpired() {
        let session = PairingSession(code: "ABC123", expiresIn: 300)
        XCTAssertFalse(session.isExpired)
    }

    func testSessionInitialState() {
        let session = PairingSession(code: "XYZ789")
        XCTAssertEqual(session.status, .pending)
        XCTAssertNil(session.sessionToken)
        XCTAssertNil(session.userInfo)
    }
}

// MARK: - AnyCodable Tests

final class AnyCodableTests: XCTestCase {

    func testStringEncoding() throws {
        let value = AnyCodable("hello")
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? String, "hello")
    }

    func testIntEncoding() throws {
        let value = AnyCodable(42)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Int, 42)
    }

    func testBoolEncoding() throws {
        let value = AnyCodable(true)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Bool, true)
    }

    func testDoubleEncoding() throws {
        let value = AnyCodable(3.14)
        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(AnyCodable.self, from: data)
        XCTAssertEqual(decoded.value as? Double, 3.14, accuracy: 0.001)
    }
}

// MARK: - PatreonPagination Tests

final class PatreonPaginationTests: XCTestCase {

    func testPaginationDecoding() throws {
        let json = """
        {
            "cursors": {"next": "abc123"},
            "total": 50
        }
        """
        let data = json.data(using: .utf8)!
        let pagination = try JSONDecoder().decode(PatreonPagination.self, from: data)
        XCTAssertEqual(pagination.cursors?.next, "abc123")
        XCTAssertEqual(pagination.total, 50)
    }

    func testEmptyPagination() throws {
        let json = "{}"
        let data = json.data(using: .utf8)!
        let pagination = try JSONDecoder().decode(PatreonPagination.self, from: data)
        XCTAssertNil(pagination.cursors)
        XCTAssertNil(pagination.total)
    }
}

// MARK: - Security Tests

final class PatreonTVSecurityTests: XCTestCase {

    func testNoHardcodedAPIKeys() {
        let patterns = [
            "sk-[a-zA-Z0-9]{20,}",
            "AKIA[A-Z0-9]{16}",
            "ghp_[a-zA-Z0-9]{36}",
            "xox[bpoas]-[a-zA-Z0-9-]+",
        ]

        let directories = [
            "/Volumes/Data/xcode/PatreonTV/PatreonTV",
            "/Volumes/Data/xcode/PatreonTV/Shared",
            "/Volumes/Data/xcode/PatreonTV/PatreonTV Relay",
        ]

        for dir in directories {
            let files = findSwiftFiles(in: dir)
            for file in files {
                guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                for pattern in patterns {
                    let regex = try? NSRegularExpression(pattern: pattern)
                    let matches = regex?.matches(in: content, range: NSRange(content.startIndex..., in: content)) ?? []
                    XCTAssertEqual(matches.count, 0, "Potential hardcoded secret found in \(file)")
                }
            }
        }
    }

    func testNovaAPIServerBindsToLoopback() {
        let serverFile = "/Volumes/Data/xcode/PatreonTV/PatreonTV/NovaAPIServer.swift"
        guard let content = try? String(contentsOfFile: serverFile, encoding: .utf8) else {
            XCTFail("Could not read NovaAPIServer.swift")
            return
        }

        XCTAssertTrue(content.contains("127.0.0.1"), "Nova API server should bind to loopback only")
        XCTAssertFalse(content.contains("0.0.0.0"), "Nova API server must NOT bind to all interfaces")
    }

    func testPairingCodeNoConfusingCharacters() {
        // Run 1000 times to check for statistical safety
        for _ in 0..<1000 {
            let code = PairingSession.generateCode()
            XCTAssertFalse(code.contains("0"), "Code should not contain '0' (confusable with 'O')")
            XCTAssertFalse(code.contains("1"), "Code should not contain '1' (confusable with 'I')")
            XCTAssertFalse(code.contains("O"), "Code should not contain 'O' (confusable with '0')")
            XCTAssertFalse(code.contains("I"), "Code should not contain 'I' (confusable with '1')")
        }
    }

    func testSessionTokenNotInUserDefaults() {
        // Check that Keychain is used for session tokens, not UserDefaults
        let files = findSwiftFiles(in: "/Volumes/Data/xcode/PatreonTV/PatreonTV")
        for file in files {
            guard let content = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (index, line) in lines.enumerated() {
                let lower = line.lowercased()
                if lower.contains("userdefaults") && (lower.contains("session") || lower.contains("token") || lower.contains("password")) {
                    // Allow if it's a comment
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.hasPrefix("//") && !trimmed.hasPrefix("/*") && !trimmed.hasPrefix("*") {
                        XCTFail("Possible session token in UserDefaults at \(file):\(index + 1): \(trimmed)")
                    }
                }
            }
        }
    }

    // MARK: - Helper

    private func findSwiftFiles(in directory: String) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: directory) else { return [] }
        var files: [String] = []
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".swift") {
                files.append("\(directory)/\(path)")
            }
        }
        return files
    }
}
