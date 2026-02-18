//
//  PostCardView.swift
//  PatreonTV
//
//  Card view for displaying a post in the feed
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

struct PostCardView: View {
    let post: PatreonPost
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                // Thumbnail/Image
                ZStack(alignment: .bottom) {
                    if let imageURL = post.thumbnailURL ?? post.imageURL,
                       let url = URL(string: imageURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(16/9, contentMode: .fill)
                            case .failure:
                                placeholderImage
                            case .empty:
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                            @unknown default:
                                placeholderImage
                            }
                        }
                        .frame(height: 220)
                        .clipped()
                    } else {
                        placeholderImage
                            .frame(height: 160)
                    }

                    // Continue Watching progress bar
                    if let progress = PlaybackProgressManager.shared.progressFraction(postID: post.id) {
                        GeometryReader { geo in
                            VStack {
                                Spacer()
                                Rectangle()
                                    .fill(PatreonColors.coral)
                                    .frame(width: geo.size.width * progress, height: 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 12) {
                    // Creator info row
                    if let campaign = post.campaign {
                        HStack(spacing: 10) {
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
                                .frame(width: 32, height: 32)
                                .clipShape(Circle())
                            }

                            Text(campaign.name)
                                .font(.system(size: 18))
                                .foregroundStyle(PatreonColors.textSecondary)

                            Spacer()

                            // Post type badge
                            postTypeBadge
                        }
                    }

                    // Title
                    Text(post.displayTitle)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(PatreonColors.textPrimary)
                        .lineLimit(2)

                    // Preview text
                    if let preview = post.previewText {
                        Text(preview)
                            .font(.system(size: 18))
                            .foregroundStyle(PatreonColors.textSecondary)
                            .lineLimit(2)
                    }

                    // Footer
                    HStack {
                        if let date = post.publishedAt {
                            Text(date, style: .relative)
                                .font(.system(size: 16))
                                .foregroundStyle(PatreonColors.textTertiary)
                        }

                        Spacer()

                        HStack(spacing: 14) {
                            if post.likeCount > 0 {
                                Label("\(post.likeCount)", systemImage: "heart.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(PatreonColors.textTertiary)
                            }
                            if post.commentCount > 0 {
                                Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(PatreonColors.textTertiary)
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(PatreonColors.glassBorder, lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.card)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }

    private var placeholderImage: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.15))

            Image(systemName: iconForPostType)
                .font(.system(size: 40))
                .foregroundStyle(PatreonColors.textTertiary)
        }
    }

    private var iconForPostType: String {
        switch post.postType {
        case .video, .videoFile, .livestream, .livestreamYoutube: return "play.rectangle.fill"
        case .audio, .audioEmbed: return "waveform"
        case .image: return "photo.fill"
        case .text: return "doc.text.fill"
        case .link: return "link"
        case .poll: return "chart.bar.fill"
        case .unknown: return "square.fill"
        }
    }

    @ViewBuilder
    private var postTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: iconForPostType)
            Text(badgeText)
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.2))
        .foregroundStyle(badgeColor)
        .cornerRadius(6)
    }

    private var badgeText: String {
        switch post.postType {
        case .video: return "Video"
        case .videoFile: return "Video"
        case .audio, .audioEmbed: return "Audio"
        case .image: return "Image"
        case .text: return "Text"
        case .link: return "Link"
        case .poll: return "Poll"
        case .livestream: return "Live"
        case .livestreamYoutube: return "YouTube"
        case .unknown: return "Post"
        }
    }

    private var badgeColor: Color {
        switch post.postType {
        case .video, .videoFile, .livestream, .livestreamYoutube: return PatreonColors.videoColor
        case .audio, .audioEmbed: return PatreonColors.audioColor
        case .image: return PatreonColors.imageColor
        case .text: return PatreonColors.textColor
        case .link: return PatreonColors.linkColor
        case .poll: return PatreonColors.pollColor
        case .unknown: return .gray
        }
    }
}

#Preview {
    PostCardView(post: PatreonPost(
        id: "1",
        title: "Sample Post Title",
        content: "This is some sample content for the post preview.",
        publishedAt: Date(),
        postType: .video,
        likeCount: 42,
        commentCount: 12,
        campaign: PatreonCampaign(
            id: "1",
            name: "Sample Creator"
        )
    ), onSelect: {})
    .frame(width: 600)
    .padding()
}
