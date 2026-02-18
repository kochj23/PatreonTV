//
//  GlassCard.swift
//  PatreonTV
//
//  Glass morphism card component
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

/// ViewModifier for glassmorphic card styling
struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 20
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(PatreonColors.glassBorder, lineWidth: 1)
                    )
            )
    }
}

extension View {
    /// Apply glassmorphic card styling
    func glassCard(cornerRadius: CGFloat = 20, padding: CGFloat = 20) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius, padding: padding))
    }
}
