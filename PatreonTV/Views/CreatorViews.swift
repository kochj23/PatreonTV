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

    var body: some View {
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
                        .fill(Color.orange.opacity(0.3))
                }
                .frame(height: 150)
                .clipped()
            } else {
                Rectangle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(height: 150)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(.white.opacity(0.5))
                    }
            }

            // Info
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
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
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .offset(y: -25)
                    }

                    Spacer()
                }

                // Name
                Text(campaign.name)
                    .font(.headline)
                    .lineLimit(1)

                // Creation name or summary
                if let creationName = campaign.creationName {
                    Text("Creating \(creationName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let summary = campaign.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Patron count
                if let patronCount = campaign.patronCount {
                    Text("\(patronCount) patrons")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
        .focusable()
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
                        LazyVStack(spacing: 30) {
                            ForEach(viewModel.posts) { post in
                                PostCardView(post: post)
                                    .onTapGesture {
                                        selectedPost = post
                                    }
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
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.vertical, 30)
                            }
                        }
                    }
                }
                .padding(60)
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
            .sheet(item: $selectedPost) { post in
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
                        .fill(Color.orange.opacity(0.3))
                }
                .frame(height: 300)
                .clipped()
                .cornerRadius(20)
            }

            HStack(spacing: 20) {
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
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(campaign.name)
                        .font(.title)
                        .fontWeight(.bold)

                    if let creationName = campaign.creationName {
                        Text("Creating \(creationName)")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    if let patronCount = campaign.patronCount {
                        Text("\(patronCount) patrons")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()
            }

            // Summary
            if let summary = campaign.summary {
                Text(summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("No posts yet")
                .font(.title3)

            Text("This creator hasn't posted any content yet")
                .font(.body)
                .foregroundStyle(.secondary)
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
    ))
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
