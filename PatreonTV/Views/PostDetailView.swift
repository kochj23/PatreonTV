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

struct PostDetailView: View {
    let post: PatreonPost
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var isPlaying = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    // Video/Audio Player
                    if post.hasVideo || post.hasAudio {
                        mediaPlayerView
                    } else if let imageURL = post.imageURL,
                              let url = URL(string: imageURL) {
                        // Image
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: 600)
                        .cornerRadius(12)
                    }

                    // Post info
                    VStack(alignment: .leading, spacing: 16) {
                        // Creator
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
                                    .frame(width: 50, height: 50)
                                    .clipShape(Circle())
                                }

                                VStack(alignment: .leading) {
                                    Text(campaign.name)
                                        .font(.headline)
                                    if let date = post.publishedAt {
                                        Text(date, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }

                        // Title
                        Text(post.displayTitle)
                            .font(.title)
                            .fontWeight(.bold)

                        // Content
                        if let content = post.content {
                            // Strip HTML for now (could use AttributedString for rich text)
                            let strippedContent = content.replacingOccurrences(
                                of: "<[^>]+>",
                                with: "",
                                options: .regularExpression
                            )
                            Text(strippedContent)
                                .font(.body)
                                .lineSpacing(8)
                        }

                        // Engagement stats
                        HStack(spacing: 24) {
                            Label("\(post.likeCount) likes", systemImage: "heart.fill")
                            Label("\(post.commentCount) comments", systemImage: "bubble.right.fill")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }
                .padding(60)
            }
            .navigationTitle(post.displayTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            player?.pause()
        }
    }

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
            // Loading or play button
            ZStack {
                if let thumbnailURL = post.thumbnailURL ?? post.imageURL,
                   let url = URL(string: thumbnailURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                }

                // Play button overlay
                Button {
                    loadAndPlayMedia()
                } label: {
                    Image(systemName: post.hasAudio ? "waveform.circle.fill" : "play.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.white)
                        .shadow(radius: 10)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 500)
            .cornerRadius(12)
        }
    }

    private func loadAndPlayMedia() {
        // Try to get video URL
        var mediaURL: URL?

        if let embedURL = post.embedURL {
            // Handle embedded videos (YouTube, Vimeo, etc.)
            // For now, try to use directly
            mediaURL = URL(string: embedURL)
        } else if let videoURL = post.videoURL {
            mediaURL = URL(string: videoURL)
        } else if let audioURL = post.audioURL {
            mediaURL = URL(string: audioURL)
        }

        if let url = mediaURL {
            player = AVPlayer(url: url)
            player?.play()
            isPlaying = true
        }
    }
}

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
