//
//  HomeView.swift
//  PatreonTV
//
//  Main home screen showing feed and navigation
//
//  Created by Jordan Koch on 2026-02-09.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject var authManager: AuthManager
    @StateObject private var viewModel = HomeViewModel()
    @State private var selectedTab = 0

    var body: some View {
        ZStack {
            GlassmorphicBackground()

            TabView(selection: $selectedTab) {
                // Feed Tab
                FeedView(viewModel: viewModel)
                    .tabItem {
                        Label("Feed", systemImage: "rectangle.stack.fill")
                    }
                    .tag(0)

                // Creators Tab
                CreatorsView(viewModel: viewModel)
                    .tabItem {
                        Label("Creators", systemImage: "person.2.fill")
                    }
                    .tag(1)

                // Settings Tab
                SettingsView()
                    .tabItem {
                        Label("Settings", systemImage: "gear")
                    }
                    .tag(2)
            }
        }
        .task {
            await viewModel.loadInitialData()
        }
    }
}

// MARK: - Feed View

struct FeedView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var selectedPost: PatreonPost?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Creator filter chips
                    if !viewModel.uniqueFeedCreators.isEmpty {
                        CreatorFilterBar(viewModel: viewModel)
                            .padding(.bottom, 30)
                    }

                    LazyVStack(spacing: 80) {
                        if viewModel.isLoadingFeed && viewModel.feedPosts.isEmpty {
                            ProgressView("Loading feed...")
                                .padding(.top, 100)
                        } else if viewModel.filteredFeedPosts.isEmpty && viewModel.selectedCreatorFilter != nil {
                            // Filtered to empty — show hint
                            VStack(spacing: 16) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 50))
                                    .foregroundStyle(PatreonColors.textTertiary)
                                Text("No posts from this creator in your feed")
                                    .font(.system(size: 24))
                                    .foregroundStyle(PatreonColors.textSecondary)
                                Button("Show All") {
                                    viewModel.selectedCreatorFilter = nil
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.top, 80)
                        } else if viewModel.feedPosts.isEmpty {
                            emptyStateView
                        } else {
                            ForEach(viewModel.filteredFeedPosts) { post in
                                PostCardView(post: post) {
                                    selectedPost = post
                                }
                                .frame(maxWidth: 800)
                            }

                            // Load more button (only show when not filtering)
                            if viewModel.hasMoreFeedPosts && viewModel.selectedCreatorFilter == nil {
                                Button {
                                    Task {
                                        await viewModel.loadMoreFeed()
                                    }
                                } label: {
                                    if viewModel.isLoadingFeed {
                                        ProgressView()
                                    } else {
                                        Text("Load More")
                                            .font(.system(size: 22))
                                    }
                                }
                                .buttonStyle(.bordered)
                                .padding(.vertical, 40)
                            }
                        }
                    }
                }
                .padding(.horizontal, 80)
                .padding(.vertical, 60)
            }
            .navigationTitle("Your Feed")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.refreshFeed() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingFeed)
                }
            }
            .fullScreenCover(item: $selectedPost) { post in
                PostDetailView(post: post, allPosts: viewModel.filteredFeedPosts)
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("PlayNextPost"))) { notification in
                if let postID = notification.userInfo?["postID"] as? String,
                   let nextPost = viewModel.filteredFeedPosts.first(where: { $0.id == postID }) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        selectedPost = nextPost
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("DeepLinkToPost"))) { notification in
                if let postID = notification.userInfo?["postID"] as? String,
                   let post = viewModel.feedPosts.first(where: { $0.id == postID }) {
                    selectedPost = post
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundStyle(PatreonColors.textTertiary)

            Text("No posts yet")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(PatreonColors.textPrimary)

            Text("Posts from creators you support will appear here")
                .font(.system(size: 22))
                .foregroundStyle(PatreonColors.textSecondary)
        }
        .padding(.top, 100)
    }
}

// MARK: - Creators View

struct CreatorsView: View {
    @ObservedObject var viewModel: HomeViewModel
    @State private var selectedCampaign: PatreonCampaign?

    var body: some View {
        NavigationStack {
            ScrollView {
                if viewModel.isLoadingCreators && viewModel.campaigns.isEmpty {
                    ProgressView("Loading creators...")
                        .padding(.top, 100)
                } else if viewModel.campaigns.isEmpty {
                    emptyStateView
                } else {
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 40),
                        GridItem(.flexible(), spacing: 40),
                        GridItem(.flexible(), spacing: 40)
                    ], spacing: 40) {
                        ForEach(viewModel.campaigns) { campaign in
                            CreatorCardView(campaign: campaign) {
                                selectedCampaign = campaign
                            }
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 60)
                }
            }
            .navigationTitle("Creators You Support")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.loadCreators() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingCreators)
                }
            }
            .fullScreenCover(item: $selectedCampaign) { campaign in
                CreatorDetailView(campaign: campaign)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 60))
                .foregroundStyle(PatreonColors.textTertiary)

            Text("No creators found")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(PatreonColors.textPrimary)

            Text("Creators you support on Patreon will appear here")
                .font(.system(size: 22))
                .foregroundStyle(PatreonColors.textSecondary)
        }
        .padding(.top, 100)
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        NavigationStack {
            List {
                // Account section
                Section("Account") {
                    if let user = authManager.currentUser {
                        HStack {
                            AsyncImage(url: URL(string: user.imageURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Image(systemName: "person.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())

                            VStack(alignment: .leading) {
                                Text(user.fullName)
                                    .font(.headline)
                                if let email = user.email {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // About section
                Section("About") {
                    LabeledContent("Version", value: "1.0.0")
                    LabeledContent("Developer", value: "Jordan Koch")
                }

                // Support section
                Section("Support") {
                    Text("For help, visit github.com/kochj23/PatreonTV")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

// MARK: - Creator Filter Bar

struct CreatorFilterBar: View {
    @ObservedObject var viewModel: HomeViewModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                FilterChip(
                    label: "All",
                    isSelected: viewModel.selectedCreatorFilter == nil
                ) {
                    viewModel.selectedCreatorFilter = nil
                }

                ForEach(viewModel.uniqueFeedCreators) { campaign in
                    FilterChip(
                        label: campaign.name,
                        avatarURL: campaign.avatarURL,
                        isSelected: viewModel.selectedCreatorFilter == campaign.id
                    ) {
                        viewModel.selectedCreatorFilter = campaign.id
                    }
                }
            }
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let label: String
    var avatarURL: String?
    let isSelected: Bool
    let action: () -> Void
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let avatarStr = avatarURL, let url = URL(string: avatarStr) {
                    AsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                    }
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                }

                Text(label)
                    .font(.system(size: 18, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? PatreonColors.coral : Color.white.opacity(0.1))
            )
            .foregroundStyle(isSelected ? .white : PatreonColors.textSecondary)
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .scaleEffect(isFocused ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    @Published var feedPosts: [PatreonPost] = []
    @Published var campaigns: [PatreonCampaign] = []
    @Published var isLoadingFeed = false
    @Published var isLoadingCreators = false
    @Published var hasMoreFeedPosts = true
    @Published var errorMessage: String?
    @Published var selectedCreatorFilter: String?  // campaign ID, nil = "All"

    /// Feed posts filtered by selected creator (nil = show all)
    var filteredFeedPosts: [PatreonPost] {
        guard let filterID = selectedCreatorFilter else { return feedPosts }
        return feedPosts.filter { $0.campaign?.id == filterID }
    }

    /// Unique creators extracted from feed, for filter chips
    var uniqueFeedCreators: [PatreonCampaign] {
        var seen = Set<String>()
        return feedPosts.compactMap { post -> PatreonCampaign? in
            guard let c = post.campaign, !seen.contains(c.id) else { return nil }
            seen.insert(c.id)
            return c
        }
    }

    private var feedCursor: String?
    private let api = PatreonAPI.shared

    func loadInitialData() async {
        // Load feed first so creators fallback has data if fetchMemberships fails
        await loadFeed()
        await loadCreators()
    }

    func loadFeed() async {
        guard !isLoadingFeed else { return }
        isLoadingFeed = true
        feedCursor = nil

        do {
            let (posts, cursor) = try await api.fetchHomeFeed()
            feedPosts = posts
            feedCursor = cursor
            hasMoreFeedPosts = cursor != nil
            updateTopShelfData()
        } catch {
            errorMessage = error.localizedDescription
            print("[HomeViewModel] Error loading feed: \(error)")
        }

        isLoadingFeed = false
    }

    func loadMoreFeed() async {
        guard !isLoadingFeed, let cursor = feedCursor else { return }
        isLoadingFeed = true

        do {
            let (posts, newCursor) = try await api.fetchHomeFeed(cursor: cursor)
            feedPosts.append(contentsOf: posts)
            feedCursor = newCursor
            hasMoreFeedPosts = newCursor != nil
        } catch {
            errorMessage = error.localizedDescription
            print("[HomeViewModel] Error loading more feed: \(error)")
        }

        isLoadingFeed = false
    }

    func refreshFeed() async {
        await loadFeed()
    }

    func loadCreators() async {
        guard !isLoadingCreators else { return }
        isLoadingCreators = true

        do {
            campaigns = try await api.fetchMemberships()
        } catch {
            print("[HomeViewModel] fetchMemberships failed: \(error), falling back to feed extraction")
            // Fallback: extract unique campaigns from feed posts
            if feedPosts.isEmpty {
                do {
                    let (posts, cursor) = try await api.fetchHomeFeed()
                    feedPosts = posts
                    feedCursor = cursor
                    hasMoreFeedPosts = cursor != nil
                } catch {
                    print("[HomeViewModel] Feed fallback also failed: \(error)")
                }
            }
            var seen = Set<String>()
            var extracted: [PatreonCampaign] = []
            for post in feedPosts {
                if let campaign = post.campaign, !seen.contains(campaign.id) {
                    seen.insert(campaign.id)
                    extracted.append(campaign)
                }
            }
            campaigns = extracted
            if campaigns.isEmpty {
                errorMessage = "Could not load creators. Please try refreshing."
            }
        }

        isLoadingCreators = false
    }

    // MARK: - Top Shelf Data Sharing

    /// Write recent posts to App Group container for the Top Shelf extension
    private func updateTopShelfData() {
        let topPosts = Array(feedPosts.prefix(10)).map { post in
            TopShelfPostData(
                id: post.id,
                title: post.displayTitle,
                thumbnailURL: post.thumbnailURL ?? post.imageURL,
                campaignName: post.campaign?.name,
                postType: post.postType.rawValue
            )
        }

        guard let sharedDefaults = UserDefaults(suiteName: "group.com.jordankoch.patreontv") else {
            print("[HomeViewModel] Could not access App Group container")
            return
        }

        do {
            let data = try JSONEncoder().encode(topPosts)
            sharedDefaults.set(data, forKey: "top_shelf_posts")
            print("[HomeViewModel] Updated Top Shelf with \(topPosts.count) posts")
        } catch {
            print("[HomeViewModel] Failed to encode Top Shelf data: \(error)")
        }
    }
}

/// Lightweight model for sharing post data with Top Shelf extension
struct TopShelfPostData: Codable {
    let id: String
    let title: String
    let thumbnailURL: String?
    let campaignName: String?
    let postType: String
}

#Preview {
    HomeView()
        .environmentObject(AuthManager.shared)
}
