import Foundation

/// Geometry in AppKit screen coordinates (points, y up). Reserves the whole bubble window,
/// so streaming text can grow without covering the source or moving on every token.
enum SelectionPlacement {
    struct Result {
        let bubbleFrame: CGRect
        let feet: CGPoint
        let isBelow: Bool
    }

    static let clearance: CGFloat = 12
    static let minimumBubble = CGSize(width: 260, height: 160)

    static func place(avoiding selection: CGRect, near anchor: CGPoint, screens: [CGRect],
                      preferredSize: CGSize, petHead: CGFloat, petHalfWidth: CGFloat) -> Result? {
        let excluded = selection.insetBy(dx: -clearance, dy: -clearance)
        var candidates: [(result: Result, sizeLoss: CGFloat, distance: CGFloat, screen: Int, order: Int)] = []
        for (screenIndex, screen) in screens.enumerated() where screen.width > 0 && screen.height > 0 {
            let cut = excluded.intersection(screen)
            let regions: [(CGRect, Bool)]
            if cut.isNull || cut.isEmpty {
                regions = [(screen, true)]
            } else {
                // Prefer below, then above; use either side for tall selections.
                regions = [
                    (CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: cut.minY - screen.minY), true),
                    (CGRect(x: screen.minX, y: cut.maxY, width: screen.width, height: screen.maxY - cut.maxY), false),
                    (CGRect(x: cut.maxX, y: screen.minY, width: screen.maxX - cut.maxX, height: screen.height), true),
                    (CGRect(x: screen.minX, y: screen.minY, width: cut.minX - screen.minX, height: screen.height), true),
                ]
            }
            for (order, entry) in regions.enumerated() {
                let (freeRegion, below) = entry
                // Leave a point at the boundary for fractional scales and pixel rounding.
                guard freeRegion.width > 2, freeRegion.height > 2 else { continue }
                let region = freeRegion.insetBy(dx: 1, dy: 1)
                // Transparent margins overlap the ears/paws, matching the ordinary bubble layout.
                let overlap: CGFloat = petHead > 0 ? (below ? 12 : 18) : 0
                let height = min(preferredSize.height, region.height - petHead + overlap)
                let width = min(preferredSize.width, region.width)
                guard width >= minimumBubble.width, height >= minimumBubble.height,
                      width >= petHalfWidth * 2 else { continue }
                let groupHeight = height + petHead - overlap
                let x = clamp(anchor.x - width / 2, region.minX, region.maxX - width)
                let desiredY = below ? anchor.y - groupHeight : anchor.y
                let y = clamp(desiredY, region.minY, region.maxY - groupHeight)
                let feetY = below ? y + height - overlap : y
                let frame = CGRect(x: x, y: below ? y : y + petHead - overlap, width: width, height: height)
                guard !frame.intersects(excluded), screen.contains(frame) else { continue }
                let feet = CGPoint(x: clamp(anchor.x, x + petHalfWidth, x + width - petHalfWidth), y: feetY)
                let distance = hypot(frame.midX - anchor.x, frame.midY - anchor.y)
                candidates.append((Result(bubbleFrame: frame, feet: feet, isBelow: below),
                                   preferredSize.width * preferredSize.height - width * height,
                                   distance, screenIndex, order))
            }
        }
        // Keep the result on the selection's display if possible, then maximize readable space.
        return candidates.min {
            if $0.screen != $1.screen { return $0.screen < $1.screen }
            if $0.sizeLoss != $1.sizeLoss { return $0.sizeLoss < $1.sizeLoss }
            if $0.order != $1.order { return $0.order < $1.order }
            return $0.distance < $1.distance
        }?.result
    }

    /// AX coordinates use the top-left of the primary display, not the active display.
    static func appKitRect(_ axRect: CGRect, primaryTop: CGFloat) -> CGRect? {
        guard axRect.minX.isFinite, axRect.minY.isFinite, axRect.width.isFinite, axRect.height.isFinite,
              axRect.width > 0, axRect.height > 0 else { return nil }
        return CGRect(x: axRect.minX, y: primaryTop - axRect.maxY, width: axRect.width, height: axRect.height)
    }

    /// Without AX bounds, reserve the full line band, including reverse drags and wrapped lines.
    static func fallback(start: CGPoint, end: CGPoint, screen: CGRect) -> CGRect {
        CGRect(x: screen.minX, y: min(start.y, end.y) - 24,
               width: screen.width, height: abs(end.y - start.y) + 48)
    }

    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), max(lower, upper))
    }
}
