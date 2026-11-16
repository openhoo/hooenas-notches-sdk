// SPDX-License-Identifier: FSL-1.1-MIT
// Copyright (c) 2026 Cua AI, Inc.
// Adapted for Hooenas Notches: custom cubic contours, softer default radii and public shape API.
// Source: https://github.com/trycua/cua/blob/1f9b3184d3978c11ca06b121aee27e4b284275f9/libs/spaces-notch-swift/Sources/CuaSpacesNotchUI/NotchContentView.swift
// The upstream shape credits DynamicNotchKit, Copyright (c) 2025 Kai Azim (MIT).
// See THIRD_PARTY_NOTICES.md and LICENSES/Cua-Spaces-Notch-LICENSE.txt.

import SwiftUI

/// An animatable contour with soft concave shoulders and rounded lower corners.
/// Both radii interpolate continuously as the surface expands.
/// See THIRD_PARTY_NOTICES.md for the original geometry's provenance.
public struct ContourNotchShape: Shape {
    public var top: CGFloat
    public var bottom: CGFloat

    public init(top: CGFloat = 8, bottom: CGFloat = 16) {
        self.top = top
        self.bottom = bottom
    }

    public var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set {
            top = newValue.first
            bottom = newValue.second
        }
    }

    public func path(in rect: CGRect) -> Path {
        guard rect.width > 0, rect.height > 0, rect.width.isFinite, rect.height.isFinite,
            rect.minX.isFinite, rect.minY.isFinite, rect.maxX.isFinite, rect.maxY.isFinite
        else { return Path() }
        var p = Path()
        let t = max(0, min(top.isFinite ? top : 8, rect.width / 4, rect.height / 2))
        let b = max(0, min(bottom.isFinite ? bottom : 16, rect.height / 2, (rect.width - 2 * t) / 2))
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addCurve(
            to: CGPoint(x: rect.minX + t, y: rect.minY + t),
            control1: CGPoint(x: rect.minX + t * 0.68, y: rect.minY),
            control2: CGPoint(x: rect.minX + t, y: rect.minY + t * 0.32)
        )
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addCurve(
            to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
            control1: CGPoint(x: rect.minX + t, y: rect.maxY - b * 0.36),
            control2: CGPoint(x: rect.minX + t + b * 0.36, y: rect.maxY)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addCurve(
            to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
            control1: CGPoint(x: rect.maxX - t - b * 0.36, y: rect.maxY),
            control2: CGPoint(x: rect.maxX - t, y: rect.maxY - b * 0.36)
        )
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - t, y: rect.minY + t * 0.32),
            control2: CGPoint(x: rect.maxX - t * 0.68, y: rect.minY)
        )
        p.closeSubpath()
        return p
    }
}
