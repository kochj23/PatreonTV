//
//  CreatorViews.swift
//  PatreonTV
//
//  Views for displaying creator/campaign information
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

// MARK: - Creator Card View

/// Card view for displaying a creator in the grid
struct CreatorCardView: View {
    let campaign: PatreonCampaign
    let onSelect: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 0) {
                // Cover image
                if let coverURL = campaign.coverPhotoURL ?? campaign.avatarURL,
                   let url = URL(string: coverURL) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                    } placeholder: {
                        Rectangle()
                            .fill(PatreonColors.coral.opacity(0.2))
                    }
                    .frame(height: 130)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(PatreonColors.coral.opacity(0.2))
                        .frame(height: 130)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(PatreonColors.textTertiary)
                        }
                }

                // Info
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        // Avatar
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
                            .offset(y: -20)
                        }
                        Spacer()
                    }

                    // Name
                    Text(campaign.name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(PatreonColors.textPrimary)
                        .lineLimit(1)

                    // Creation name or summary
                    if let creationName = campaign.creationName {
                        Text("Creating \(creationName)")
                            .font(.system(size: 16))
                            .foregroundStyle(PatreonColors.textSecondary)
                            .lineLimit(1)
                    } else if let summary = campaign.summary {
                        Text(summary)
                            .font(.system(size: 16))
                            .foregroundStyle(PatreonColors.textSecondary)
                            .lineLimit(2)
                    }

                    // Patron count
                    if let patronCount = campaign.patronCount {
                        Text("\(patronCount) patrons")
                            .font(.system(size: 14))
                            .foregroundStyle(PatreonColors.textTertiary)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Creator Detail View

/// Full page view for a creator showing their posts
struct CreatorDetailView: View {
    let campaign: PatreonCampaign
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = CreatorDetailViewModel()
    @State private var selectedPost: PatreonPost?

    var body: some View {
        NavigationStack {
            ZStack {
                GlassmorphicBackground()

                ScrollView {
                    VStack(spacing: 40) {
                        // Header
                        headerView

                        // Posts
                        if viewModel.isLoading && viewModel.posts.isEmpty {
                            ProgressView("Loading posts...")
                                .padding(.top, 60)
                        } else if viewModel.posts.isEmpty {
                            emptyStateView
                        } else {
                            LazyVStack(spacing: 80) {
                                ForEach(viewModel.posts) { post in
                                    PostCardView(post: post) {
                                        selectedPost = post
                                    }
                                    .frame(maxWidth: 800)
                                }

                                // Load more
                                if viewModel.hasMore {
                                    Button {
                                        Task {
                                            await viewModel.loadMore(campaignId: campaign.id)
                                        }
                                    } label: {
                                        if viewModel.isLoading {
                                            ProgressView()
                                        } else {
                                            Text("Load More")
                                                .font(.system(size: 22))
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .padding(.vertical, 30)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                }
            }
            .navigationTitle(campaign.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                await viewModel.loadPosts(campaignId: campaign.id)
            }
            .fullScreenCover(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 20) {
            // Cover image
            if let coverURL = campaign.coverPhotoURL,
               let url = URL(string: coverURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(21/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(PatreonColors.coral.opacity(0.2))
                }
                .frame(height: 250)
                .clipped()
                .cornerRadius(20)
            }

            HStack(spacing: 16) {
                // Avatar
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
                    .frame(width: 80, height: 80)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(campaign.name)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(PatreonColors.textPrimary)

                    if let creationName = campaign.creationName {
                        Text("Creating \(creationName)")
                            .font(.system(size: 22))
                            .foregroundStyle(PatreonColors.textSecondary)
                    }

                    if let patronCount = campaign.patronCount {
                        Text("\(patronCount) patrons")
                            .font(.system(size: 18))
                            .foregroundStyle(PatreonColors.textTertiary)
                    }
                }

                Spacer()
            }

            // Summary
            if let summary = campaign.summary {
                Text(summary)
                    .font(.system(size: 20))
                    .foregroundStyle(PatreonColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 50))
                .foregroundStyle(PatreonColors.textTertiary)

            Text("No posts yet")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(PatreonColors.textPrimary)

            Text("This creator hasn't posted any content yet")
                .font(.system(size: 20))
                .foregroundStyle(PatreonColors.textSecondary)
        }
        .padding(.top, 60)
    }
}

// MARK: - Creator Detail View Model

@MainActor
class CreatorDetailViewModel: ObservableObject {
    @Published var posts: [PatreonPost] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published var errorMessage: String?

    private var cursor: String?
    private let api = PatreonAPI.shared

    func loadPosts(campaignId: String) async {
        guard !isLoading else { return }
        isLoading = true
        cursor = nil

        do {
            let (fetchedPosts, nextCursor) = try await api.fetchCampaignPosts(campaignId: campaignId)
            posts = fetchedPosts
            cursor = nextCursor
            hasMore = nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
            print("[CreatorDetailViewModel] Error loading posts: \(error)")
        }

        isLoading = false
    }

    func loadMore(campaignId: String) async {
        guard !isLoading, let currentCursor = cursor else { return }
        isLoading = true

        do {
            let (fetchedPosts, nextCursor) = try await api.fetchCampaignPosts(
                campaignId: campaignId,
                cursor: currentCursor
            )
            posts.append(contentsOf: fetchedPosts)
            cursor = nextCursor
            hasMore = nextCursor != nil
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}

// MARK: - Previews

#Preview("Creator Card") {
    CreatorCardView(campaign: PatreonCampaign(
        id: "1",
        name: "Sample Creator",
        summary: "Creating awesome content for everyone!",
        creationName: "videos and podcasts",
        patronCount: 1234
    ), onSelect: {})
    .frame(width: 350)
    .padding()
}

#Preview("Creator Detail") {
    CreatorDetailView(campaign: PatreonCampaign(
        id: "1",
        name: "Sample Creator",
        summary: "Creating awesome content for everyone!",
        creationName: "videos and podcasts",
        patronCount: 1234
    ))
}
