// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.

import SwiftUI
import VelaMedia

extension GIFProvider {
    /// Whether the site's GIFs carry its watermark in the conversation.
    /// KLIPY's attribution guidelines recommend one, in the bottom-left
    /// corner; the other sites ask for none.
    var showsWatermark: Bool { self == .klipy }
}

/// The bottom-left corner of an inline GIF or animated image: the "GIF"
/// badge, and with `watermark` (a KLIPY GIF whose picture is showing)
/// KLIPY's watermark in the corner, with the badge after it.
///
/// The watermark is KLIPY's own file (`KLIPYLogo.watermark`), as it comes:
/// its white is already see-through, and a dark outline keeps it readable
/// on white. It sizes itself to the GIF (`GIFCornerLayout`), takes no
/// clicks or hovering (they go to the GIF), and VoiceOver skips it: the
/// "via KLIPY" line under the GIF names KLIPY.
struct GIFCornerMarks<Badge: View>: View {
    @Environment(\.displayScale) private var displayScale
    let watermark: Bool
    let compact: Bool
    @ViewBuilder let badge: () -> Badge

    var body: some View {
        let inset: CGFloat = compact ? 4 : 8
        // Drawn at its largest and scaled down: one bitmap for every size.
        if watermark, let image = KLIPYLogo.watermark.rendered(height: GIFCornerLayout.maxWatermarkHeight, scale: displayScale) {
            GIFCornerLayout(inset: inset, spacing: compact ? 4 : 5, watermarkAspectRatio: KLIPYLogo.watermark.aspectRatio) {
                Image(decorative: image, scale: displayScale)
                    .resizable()
                    .interpolation(.high)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                badge()
            }
        } else {
            badge().padding(inset)
        }
    }
}

/// Lays out `GIFCornerMarks` over the whole GIF: the watermark (the first
/// subview) in the bottom-left corner, `inset` from the edges, and the badge
/// (any other subview) after it, centered on it. A GIF too narrow for both
/// side by side has the badge above the watermark.
///
/// The watermark's height follows the GIF's shorter side, between
/// `minWatermarkHeight` (thumbnails, small GIFs) and `maxWatermarkHeight`.
/// Only arithmetic: no measuring, nothing kept.
struct GIFCornerLayout: Layout {
    var inset: CGFloat
    var spacing: CGFloat
    /// The watermark's width over its height.
    var watermarkAspectRatio: CGFloat

    static let minWatermarkHeight: CGFloat = 9
    static let maxWatermarkHeight: CGFloat = 12

    /// The watermark's height on a GIF of `size`: a twentieth of its shorter
    /// side, in whole points, within the limits.
    static func watermarkHeight(for size: CGSize) -> CGFloat {
        min(maxWatermarkHeight, max(minWatermarkHeight, (min(size.width, size.height) / 20).rounded()))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let mark = subviews.first else { return }
        let height = Self.watermarkHeight(for: bounds.size)
        let markSize = CGSize(width: (height * watermarkAspectRatio).rounded(), height: height)
        let badges = subviews.dropFirst()
        let badgeSize = badges.first?.sizeThatFits(.unspecified) ?? .zero
        let left = bounds.minX + inset
        let bottom = bounds.maxY - inset
        guard badgeSize != .zero else {
            mark.place(at: CGPoint(x: left, y: bottom - markSize.height), proposal: ProposedViewSize(markSize))
            return
        }
        let rowWidth = markSize.width + spacing + badgeSize.width
        if rowWidth <= bounds.width - inset * 2 {
            // One row, as tall as the taller of the two: the badge stays
            // where it is on other GIFs, just moved along.
            let middle = bottom - max(markSize.height, badgeSize.height) / 2
            mark.place(at: CGPoint(x: left, y: middle), anchor: .leading, proposal: ProposedViewSize(markSize))
            for badge in badges {
                badge.place(at: CGPoint(x: left + markSize.width + spacing, y: middle), anchor: .leading, proposal: ProposedViewSize(badgeSize))
            }
        } else {
            mark.place(at: CGPoint(x: left, y: bottom - markSize.height), proposal: ProposedViewSize(markSize))
            for badge in badges {
                badge.place(
                    at: CGPoint(x: left, y: bottom - markSize.height - spacing),
                    anchor: .bottomLeading,
                    proposal: ProposedViewSize(badgeSize)
                )
            }
        }
    }
}
