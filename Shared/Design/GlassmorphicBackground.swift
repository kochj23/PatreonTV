//
//  GlassmorphicBackground.swift
//  PatreonTV
//
//  Animated glassmorphic background with floating blobs
//
//  Created by Jordan Koch on 2026-02-17.
//  Copyright © 2026 Jordan Koch. All rights reserved.
//  Licensed under MIT License
//

import SwiftUI

/// Animated background with floating colored blobs (Patreon theme)
struct GlassmorphicBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Base gradient
            LinearGradient.patreonBackground
                .ignoresSafeArea()

            // Animated blobs
            GeometryReader { geometry in
                ZStack {
                    // Coral blob
                    FloatingBlob(color: PatreonColors.coral.opacity(0.25), size: geometry.size.width * 0.5)
                        .offset(
                            x: animate ? geometry.size.width * 0.3 : geometry.size.width * 0.1,
                            y: animate ? geometry.size.height * 0.2 : geometry.size.height * 0.4
                        )

                    // Orange blob
                    FloatingBlob(color: PatreonColors.warmOrange.opacity(0.2), size: geometry.size.width * 0.45)
                        .offset(
                            x: animate ? geometry.size.width * 0.6 : geometry.size.width * 0.8,
                            y: animate ? geometry.size.height * 0.6 : geometry.size.height * 0.3
                        )

                    // Purple blob
                    FloatingBlob(color: PatreonColors.purple.opacity(0.15), size: geometry.size.width * 0.35)
                        .offset(
                            x: animate ? geometry.size.width * 0.2 : geometry.size.width * 0.5,
                            y: animate ? geometry.size.height * 0.7 : geometry.size.height * 0.8
                        )
                }
            }
            .blur(radius: 80)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                animate = true
            }
        }
    }
}

/// A single floating blob shape
struct FloatingBlob: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
