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
    @State private var mediaError: String?

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
                .frame(height: 600)
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

                // Play button overlay or error
                VStack(spacing: 16) {
                    if let error = mediaError {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    } else {
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
                }
            }
            .frame(height: 600)
            .cornerRadius(12)
        }
    }

    private func loadAndPlayMedia() {
        mediaError = nil

        // Check for direct video/audio files first (native AVPlayer)
        if let videoURL = post.videoURL, let url = URL(string: videoURL) {
            playWithAVPlayer(url: url)
            return
        }

        if let audioURL = post.audioURL, let url = URL(string: audioURL) {
            playWithAVPlayer(url: url)
            return
        }

        // Check attachments for direct media URLs
        if let attachments = post.attachments {
            for attachment in attachments {
                if (attachment.isVideo || attachment.isAudio),
                   let urlStr = attachment.url, let url = URL(string: urlStr) {
                    playWithAVPlayer(url: url)
                    return
                }
            }
        }

        // For embed URLs, try to fetch the full post details which may have the video URL
        if let embedURL = post.embedURL {
            let embedLower = embedURL.lowercased()

            if embedLower.contains("youtube.com") || embedLower.contains("youtu.be") {
                mediaError = "This video is hosted on YouTube.\nOpen YouTube on your Apple TV to watch it."
                return
            }
            if embedLower.contains("vimeo.com") {
                mediaError = "This video is hosted on Vimeo.\nOpen Vimeo on your Apple TV to watch it."
                return
            }

            // Try the embed URL directly — it might be a direct file
            if let url = URL(string: embedURL) {
                playWithAVPlayer(url: url)
                return
            }
        }

        // Try fetching the full post to get video URL from the API
        Task {
            do {
                let fullPost = try await PatreonAPI.shared.fetchPost(id: post.id)
                if let videoURL = fullPost.videoURL, let url = URL(string: videoURL) {
                    playWithAVPlayer(url: url)
                    return
                }
                if let attachments = fullPost.attachments {
                    for attachment in attachments {
                        if (attachment.isVideo || attachment.isAudio),
                           let urlStr = attachment.url, let url = URL(string: urlStr) {
                            playWithAVPlayer(url: url)
                            return
                        }
                    }
                }
                mediaError = "No playable media found for this post."
            } catch {
                mediaError = "Failed to load media: \(error.localizedDescription)"
            }
        }
    }

    private func playWithAVPlayer(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.play()
        isPlaying = true
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
