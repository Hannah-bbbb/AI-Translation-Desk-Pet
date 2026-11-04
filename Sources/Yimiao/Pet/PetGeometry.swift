import Foundation

/// Window placement uses whole screen points, the precision AppKit actually retains when
/// moving a panel between Retina and non-Retina displays. Never compare an unattainable
/// fractional foot position with the window's rounded position to decide whether to jump.
enum PetGeometry {
    static func windowSize(scale: CGFloat) -> CGSize {
        CGSize(width: (PetRenderer.canvas.width * scale).rounded(),
               height: (PetRenderer.canvas.height * scale).rounded())
    }

    static func origin(forFeet feet: CGPoint, scale: CGFloat) -> CGPoint {
        // The epsilon only removes floating-point noise when converting an actual frame
        // back to feet and back again (e.g. -42 becoming -42.00000000000001).
        CGPoint(x: floor(feet.x - PetRenderer.feet.x * scale + 1e-7),
                y: floor(feet.y + PetRenderer.feet.y * scale - windowSize(scale: scale).height + 1e-7))
    }

    static func feet(in frame: CGRect, scale: CGFloat) -> CGPoint {
        CGPoint(x: frame.minX + PetRenderer.feet.x * scale,
                y: frame.maxY - PetRenderer.feet.y * scale)
    }

    static func hasArrived(frame: CGRect, at feet: CGPoint, scale: CGFloat) -> Bool {
        let target = origin(forFeet: feet, scale: scale)
        // Comparing window origins avoids accumulating x/y rounding into a false distance.
        return abs(frame.minX - target.x) < 0.5 && abs(frame.minY - target.y) < 0.5
    }

    static func onScreen(_ feet: CGPoint, screens: [CGRect], halfWidth: CGFloat, height: CGFloat) -> CGPoint {
        guard let nearest = screens.first(where: { $0.contains(feet) })
                ?? screens.min(by: { distance(from: feet, to: $0) < distance(from: feet, to: $1) }) else { return feet }
        // Check the actual screen first. Expanding screen bounds before choosing one steals
        // points near a shared edge from the neighbouring display and can move home repeatedly.
        return CGPoint(x: feet.x.clamped(nearest.minX + halfWidth...max(nearest.minX + halfWidth, nearest.maxX - halfWidth)),
                       y: feet.y.clamped(nearest.minY...max(nearest.minY, nearest.maxY - height)))
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        hypot(point.x - point.x.clamped(rect.minX...rect.maxX), point.y - point.y.clamped(rect.minY...rect.maxY))
    }
}
