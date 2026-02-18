//
//  PatreonColors.swift
//  PatreonTV
//
//  Unified color palette and design system for PatreonTV
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

/// Patreon-themed color palette with glassmorphic design
struct PatreonColors {
    // MARK: - Brand Colors

    /// Patreon coral (primary accent)
    static let coral = Color(red: 1.0, green: 0.32, blue: 0.30)

    /// Patreon warm orange
    static let warmOrange = Color(red: 1.0, green: 0.55, blue: 0.25)

    // MARK: - Accent Colors

    /// Cyan for media/video
    static let cyan = Color(red: 0.23, green: 0.86, blue: 0.98)

    /// Purple for audio
    static let purple = Color(red: 0.65, green: 0.4, blue: 1.0)

    /// Green for active/success
    static let green = Color(red: 0.3, green: 0.9, blue: 0.6)

    /// Yellow for warnings/polls
    static let yellow = Color(red: 1.0, green: 0.85, blue: 0.3)

    /// Blue for links
    static let blue = Color(red: 0.3, green: 0.6, blue: 1.0)

    /// Red for errors/destructive
    static let red = Color(red: 1.0, green: 0.3, blue: 0.4)

    // MARK: - Post Type Colors

    static let videoColor = cyan
    static let audioColor = purple
    static let imageColor = blue
    static let textColor = green
    static let linkColor = warmOrange
    static let pollColor = yellow

    // MARK: - Text Colors

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.7)
    static let textTertiary = Color.white.opacity(0.5)

    // MARK: - Background Colors

    static let backgroundStart = Color(red: 0.06, green: 0.08, blue: 0.16)
    static let backgroundEnd = Color(red: 0.10, green: 0.14, blue: 0.26)
    static let glassBackground = Color.white.opacity(0.05)
    static let glassBorder = Color.white.opacity(0.15)
}

// MARK: - Background Gradient

extension LinearGradient {
    static var patreonBackground: LinearGradient {
        LinearGradient(
            gradient: Gradient(colors: [PatreonColors.backgroundStart, PatreonColors.backgroundEnd]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
