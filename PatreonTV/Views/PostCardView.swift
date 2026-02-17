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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail/Image
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
                            .aspectRatio(16/9, contentMode: .fill)
                    @unknown default:
                        placeholderImage
                    }
                }
                .frame(height: 300)
                .clipped()
            } else {
                placeholderImage
                    .frame(height: 200)
            }

            // Content
            VStack(alignment: .leading, spacing: 16) {
                // Creator info
                if let campaign = post.campaign {
                    HStack(spacing: 12) {
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
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Spacer()

                        // Post type badge
                        postTypeBadge
                    }
                }

                // Title
                Text(post.displayTitle)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(2)

                // Preview text
                if let preview = post.previewText {
                    Text(preview)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                // Footer
                HStack {
                    // Date
                    if let date = post.publishedAt {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    // Engagement
                    HStack(spacing: 16) {
                        if post.likeCount > 0 {
                            Label("\(post.likeCount)", systemImage: "heart.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if post.commentCount > 0 {
                            Label("\(post.commentCount)", systemImage: "bubble.right.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(Color.white.opacity(0.1))
        .cornerRadius(20)
        .focusable()
    }

    private var placeholderImage: some View {
        ZStack {
            Rectangle()
                .fill(Color.gray.opacity(0.2))

            Image(systemName: iconForPostType)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
        }
    }

    private var iconForPostType: String {
        switch post.postType {
        case .video: return "play.rectangle.fill"
        case .audio: return "waveform"
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
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(badgeColor.opacity(0.2))
        .foregroundStyle(badgeColor)
        .cornerRadius(4)
    }

    private var badgeText: String {
        switch post.postType {
        case .video: return "Video"
        case .audio: return "Audio"
        case .image: return "Image"
        case .text: return "Text"
        case .link: return "Link"
        case .poll: return "Poll"
        case .unknown: return "Post"
        }
    }

    private var badgeColor: Color {
        switch post.postType {
        case .video: return .red
        case .audio: return .purple
        case .image: return .blue
        case .text: return .green
        case .link: return .orange
        case .poll: return .yellow
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
    ))
    .frame(width: 600)
    .padding()
}
