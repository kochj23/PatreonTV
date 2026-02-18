//
//  PlaybackProgressManager.swift
//  PatreonTV
//
//  Persists playback positions for Continue Watching feature.
//  Stores position/duration pairs keyed by post ID in UserDefaults.
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import Foundation

@MainActor
class PlaybackProgressManager: ObservableObject {
    static let shared = PlaybackProgressManager()

    struct ProgressEntry: Codable {
        let postID: String
        let position: Double      // seconds into media
        let duration: Double      // total duration in seconds
        let timestamp: Date       // when this entry was last updated
    }

    @Published private(set) var entries: [String: ProgressEntry] = [:]

    private let storageKey = "playback_progress"
    private let maxEntries = 50

    private init() {
        load()
    }

    // MARK: - Public API

    /// Save playback position for a post. Ignores positions near the start (< 5s)
    /// or near the end (within 10s), since those aren't useful resume points.
    func save(postID: String, position: Double, duration: Double) {
        guard duration > 0, position >= 5, position < duration - 10 else { return }

        entries[postID] = ProgressEntry(
            postID: postID,
            position: position,
            duration: duration,
            timestamp: Date()
        )
        persist()
    }

    /// Get saved progress for a post, if any
    func getProgress(postID: String) -> ProgressEntry? {
        return entries[postID]
    }

    /// Remove progress for a post (e.g., when playback completes)
    func removeProgress(postID: String) {
        entries.removeValue(forKey: postID)
        persist()
    }

    /// Returns progress as a fraction (0.0 - 1.0) for displaying on post cards
    func progressFraction(postID: String) -> Double? {
        guard let entry = entries[postID], entry.duration > 0 else { return nil }
        return min(max(entry.position / entry.duration, 0), 1)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: ProgressEntry].self, from: data)
            entries = decoded
            print("[PlaybackProgress] Loaded \(entries.count) saved positions")
        } catch {
            print("[PlaybackProgress] Failed to decode saved progress: \(error)")
        }
    }

    private func persist() {
        // Prune old entries if over limit, keeping most recent by timestamp
        if entries.count > maxEntries {
            let sorted = entries.sorted { $0.value.timestamp > $1.value.timestamp }
            let kept = Array(sorted.prefix(maxEntries)).map { ($0.key, $0.value) }
            entries = Dictionary(uniqueKeysWithValues: kept)
        }

        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[PlaybackProgress] Failed to persist progress: \(error)")
        }
    }
}
