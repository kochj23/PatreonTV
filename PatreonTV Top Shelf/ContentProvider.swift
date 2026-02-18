//
//  ContentProvider.swift
//  PatreonTV Top Shelf
//
//  Provides recent Patreon posts for the Apple TV Top Shelf.
//  Reads post data from the shared App Group container.
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import TVServices

class ContentProvider: TVTopShelfContentProvider {

    static let appGroupID = "group.com.jordankoch.patreontv"
    static let storageKey = "top_shelf_posts"

    override func loadTopShelfContent() async -> TVTopShelfContent? {
        guard let sharedDefaults = UserDefaults(suiteName: ContentProvider.appGroupID),
              let data = sharedDefaults.data(forKey: ContentProvider.storageKey) else {
            return nil
        }

        let posts: [TopShelfPost]
        do {
            posts = try JSONDecoder().decode([TopShelfPost].self, from: data)
        } catch {
            print("[TopShelf] Failed to decode posts: \(error)")
            return nil
        }

        guard !posts.isEmpty else { return nil }

        let items: [TVTopShelfSectionedItem] = posts.compactMap { post in
            let item = TVTopShelfSectionedItem(identifier: post.id)
            item.title = post.title

            if let thumbnailStr = post.thumbnailURL, let thumbnailURL = URL(string: thumbnailStr) {
                item.setImageURL(thumbnailURL, for: .screenScale1x)
                item.setImageURL(thumbnailURL, for: .screenScale2x)
            }

            // Deep link back to the app
            if let actionURL = URL(string: "patreontv://post/\(post.id)") {
                item.playAction = TVTopShelfAction(url: actionURL)
                item.displayAction = TVTopShelfAction(url: actionURL)
            }

            return item
        }

        let section = TVTopShelfItemCollection(items: items)
        section.title = "Recent Posts"

        return TVTopShelfSectionedContent(sections: [section])
    }
}

// MARK: - Top Shelf Data Model

/// Lightweight model for sharing post data between the main app and the Top Shelf extension.
/// Stored as JSON in the shared App Group UserDefaults.
struct TopShelfPost: Codable {
    let id: String
    let title: String
    let thumbnailURL: String?
    let campaignName: String?
    let postType: String
}
