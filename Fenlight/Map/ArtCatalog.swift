import SpriteKit
import UIKit

/// Every sprite in the game is requested by an ID like `building.mossbread` or `tile.grass`.
/// If Assets.xcassets has an image with that exact name, it's used. Otherwise a placeholder
/// is drawn, so the game always runs while art is unfinished. See docs/ART_SPEC.md.
@MainActor
final class ArtCatalog {
    static let shared = ArtCatalog()
    private var cache: [String: SKTexture] = [:]

    func texture(_ id: String, placeholder: () -> UIImage) -> SKTexture {
        if let cached = cache[id] { return cached }
        let image = UIImage(named: id) ?? placeholder()
        let texture = SKTexture(image: image)
        cache[id] = texture
        return texture
    }

    func building(_ def: BuildingDef) -> SKTexture {
        texture("building.\(def.id)") { Placeholder.building(def) }
    }

    func grassTile() -> SKTexture {
        texture("tile.grass") { Placeholder.tile(fill: UIColor(hex: "#8DBA6E"), speckle: UIColor(hex: "#A9CF84")) }
    }

    func murkTile() -> SKTexture {
        texture("tile.murk") { Placeholder.tile(fill: UIColor(hex: "#2E3A2C"), speckle: UIColor(hex: "#45523A")) }
    }
}

/// Simple drawn stand-ins for real art, built at the same sizes the real art should use.
enum Placeholder {
    static func tile(fill: UIColor, speckle: UIColor) -> UIImage {
        let w = IsoMath.tileWidth, h = IsoMath.tileHeight
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h)).image { ctx in
            let g = ctx.cgContext
            let diamond = CGMutablePath()
            diamond.addLines(between: [CGPoint(x: w / 2, y: 0), CGPoint(x: w, y: h / 2),
                                       CGPoint(x: w / 2, y: h), CGPoint(x: 0, y: h / 2)])
            diamond.closeSubpath()
            g.addPath(diamond)
            g.setFillColor(fill.cgColor)
            g.fillPath()

            // A few fixed speckles so the ground doesn't look flat.
            g.addPath(diamond)
            g.clip()
            g.setFillColor(speckle.cgColor)
            for (x, y, r) in [(0.30, 0.45, 3.0), (0.62, 0.35, 2.0), (0.52, 0.68, 2.5), (0.75, 0.55, 1.5)] {
                g.fillEllipse(in: CGRect(x: w * x - r, y: h * y - r, width: r * 2, height: r * 2))
            }
            g.resetClip()

            g.addPath(diamond)
            g.setStrokeColor(UIColor.black.withAlphaComponent(0.12).cgColor)
            g.setLineWidth(1)
            g.strokePath()
        }
    }

    /// An isometric block with walls, a pyramid roof in the building's colour, a door and a lit window.
    static func building(_ def: BuildingDef) -> UIImage {
        let n = CGFloat(def.size)
        let w = IsoMath.tileWidth * n, footH = IsoMath.tileHeight * n
        let wallH: CGFloat = 30 + 18 * n
        let roofH: CGFloat = 26 + 16 * n
        let canvas = CGSize(width: w, height: footH + wallH + roofH)
        let roof = UIColor(hex: def.color)

        return UIGraphicsImageRenderer(size: canvas).image { ctx in
            let g = ctx.cgContext
            // Base diamond, inset a little from the footprint edges.
            let cx = w / 2, cy = canvas.height - footH / 2
            let hw = w / 2 * 0.86, hh = footH / 2 * 0.86
            let bottom = CGPoint(x: cx, y: cy + hh)
            let left = CGPoint(x: cx - hw, y: cy)
            let right = CGPoint(x: cx + hw, y: cy)
            func up(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y - wallH) }
            let apex = CGPoint(x: cx, y: cy - wallH - roofH)

            func fill(_ pts: [CGPoint], _ color: UIColor) {
                g.beginPath()
                g.addLines(between: pts)
                g.closePath()
                g.setFillColor(color.cgColor)
                g.setStrokeColor(UIColor(hex: "#1D1A24").cgColor)
                g.setLineWidth(2)
                g.setLineJoin(.round)
                g.drawPath(using: .fillStroke)
            }

            fill([left, bottom, up(bottom), up(left)], UIColor(hex: "#E9DFC9"))     // left wall
            fill([bottom, right, up(right), up(bottom)], UIColor(hex: "#C9BCA2"))   // right wall
            fill([up(left), up(bottom), apex], roof.adjusted(by: 0.12))            // roof, lit side
            fill([up(bottom), up(right), apex], roof.adjusted(by: -0.12))          // roof, shade side

            // Door on the left wall.
            let t: CGFloat = 0.55, dw: CGFloat = 0.16 * (1 / n + 0.4)
            func onLeft(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: left.x + (bottom.x - left.x) * u, y: left.y + (bottom.y - left.y) * u - wallH * v)
            }
            fill([onLeft(t - dw, 0), onLeft(t + dw, 0), onLeft(t + dw, 0.55), onLeft(t - dw, 0.55)],
                 roof.adjusted(by: -0.25))

            // Lit window on the right wall.
            func onRight(_ u: CGFloat, _ v: CGFloat) -> CGPoint {
                CGPoint(x: bottom.x + (right.x - bottom.x) * u, y: bottom.y + (right.y - bottom.y) * u - wallH * v)
            }
            fill([onRight(0.38, 0.35), onRight(0.62, 0.35), onRight(0.62, 0.7), onRight(0.38, 0.7)],
                 UIColor(hex: "#FFD978"))
        }
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    /// Lighter (positive) or darker (negative) version of this colour.
    func adjusted(by amount: CGFloat) -> UIColor {
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        return UIColor(hue: h, saturation: s, brightness: min(1, max(0, b + amount)), alpha: a)
    }

    /// Mix toward `other` by `t` (0 = self, 1 = other).
    func blended(with other: UIColor, _ t: CGFloat) -> UIColor {
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        other.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(red: r1 + (r2 - r1) * t, green: g1 + (g2 - g1) * t,
                       blue: b1 + (b2 - b1) * t, alpha: a1 + (a2 - a1) * t)
    }
}
