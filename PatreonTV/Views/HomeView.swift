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
                LazyVStack(spacing: 40) {
                    if viewModel.isLoadingFeed && viewModel.feedPosts.isEmpty {
                        ProgressView("Loading feed...")
                            .padding(.top, 100)
                    } else if viewModel.feedPosts.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(viewModel.feedPosts) { post in
                            PostCardView(post: post)
                                .onTapGesture {
                                    selectedPost = post
                                }
                        }

                        // Load more button
                        if viewModel.hasMoreFeedPosts {
                            Button {
                                Task {
                                    await viewModel.loadMoreFeed()
                                }
                            } label: {
                                if viewModel.isLoadingFeed {
                                    ProgressView()
                                } else {
                                    Text("Load More")
                                }
                            }
                            .buttonStyle(.bordered)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .padding(60)
            }
            .navigationTitle("Your Feed")
            .refreshable {
                await viewModel.refreshFeed()
            }
            .sheet(item: $selectedPost) { post in
                PostDetailView(post: post)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("No posts yet")
                .font(.title2)

            Text("Posts from creators you support will appear here")
                .font(.body)
                .foregroundStyle(.secondary)
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
                        GridItem(.adaptive(minimum: 300, maximum: 400), spacing: 40)
                    ], spacing: 40) {
                        ForEach(viewModel.campaigns) { campaign in
                            CreatorCardView(campaign: campaign)
                                .onTapGesture {
                                    selectedCampaign = campaign
                                }
                        }
                    }
                    .padding(60)
                }
            }
            .navigationTitle("Creators You Support")
            .refreshable {
                await viewModel.loadCreators()
            }
            .sheet(item: $selectedCampaign) { campaign in
                CreatorDetailView(campaign: campaign)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 80))
                .foregroundStyle(.secondary)

            Text("No creators found")
                .font(.title2)

            Text("Creators you support on Patreon will appear here")
                .font(.body)
                .foregroundStyle(.secondary)
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

// MARK: - Home View Model

@MainActor
class HomeViewModel: ObservableObject {
    @Published var feedPosts: [PatreonPost] = []
    @Published var campaigns: [PatreonCampaign] = []
    @Published var isLoadingFeed = false
    @Published var isLoadingCreators = false
    @Published var hasMoreFeedPosts = true
    @Published var errorMessage: String?

    private var feedCursor: String?
    private let api = PatreonAPI.shared

    func loadInitialData() async {
        async let feedTask: () = loadFeed()
        async let creatorsTask: () = loadCreators()
        _ = await (feedTask, creatorsTask)
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
            errorMessage = error.localizedDescription
            print("[HomeViewModel] Error loading creators: \(error)")
        }

        isLoadingCreators = false
    }
}

#Preview {
    HomeView()
        .environmentObject(AuthManager.shared)
}
