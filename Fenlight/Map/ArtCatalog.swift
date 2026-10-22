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

    /// Stage 1 art is `building.<id>`; later stages are `building.<id>.2`, `building.<id>.3`.
    func building(_ def: BuildingDef, stage: Int = 1) -> SKTexture {
        let id = stage <= 1 ? "building.\(def.id)" : "building.\(def.id).\(stage)"
        return texture(id) {
            def.kind == .decoration ? Placeholder.decoration(def) : Placeholder.building(def, stage: stage)
        }
    }

    /// A resident walking around the map: `walker.<id>`, or a drawn figure in their colour.
    func walker(_ def: ResidentDef) -> SKTexture {
        texture("walker.\(def.id)") { Placeholder.walker(def) }
    }

    /// A resident's portrait, for SwiftUI screens. Falls back to initials on their colour.
    func portrait(_ def: ResidentDef) -> UIImage {
        UIImage(named: "resident.\(def.id)") ?? Placeholder.portrait(def)
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
    private static var portraits: [String: UIImage] = [:]

    /// A coloured circle with the resident's initials.
    static func portrait(_ def: ResidentDef) -> UIImage {
        if let cached = portraits[def.id] { return cached }
        let size = CGSize(width: 128, height: 128)
        let initials = def.name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
        let image = UIGraphicsImageRenderer(size: size).image { _ in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
            UIColor(hex: def.color).setFill()
            UIBezierPath(ovalIn: rect).fill()
            UIColor(hex: "#FFF8E6").setStroke()
            let ring = UIBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
            ring.lineWidth = 5
            ring.stroke()
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 46, weight: .heavy),
                .foregroundColor: UIColor(hex: "#FFF8E6"),
            ]
            let text = initials as NSString
            let textSize = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2),
                      withAttributes: attrs)
        }
        portraits[def.id] = image
        return image
    }

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

    /// A small figure: body in the resident's colour, a head, ears for animal-folk, wings for fae.
    /// Feet sit near the bottom centre of the image.
    static func walker(_ def: ResidentDef) -> UIImage {
        let size = CGSize(width: 48, height: 72)
        let folk = def.folk.lowercased()
        let color = UIColor(hex: def.color)
        let ink = UIColor(hex: "#1D1A24")
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            g.setLineWidth(2)
            g.setStrokeColor(ink.cgColor)
            g.setLineJoin(.round)
            func shape(_ path: CGPath, _ c: UIColor) {
                g.addPath(path)
                g.setFillColor(c.cgColor)
                g.drawPath(using: .fillStroke)
            }
            // Shadow
            g.setFillColor(UIColor.black.withAlphaComponent(0.25).cgColor)
            g.fillEllipse(in: CGRect(x: 10, y: 62, width: 28, height: 9))
            // Wings for fae, sprites and moths
            if folk.contains("fae") || folk.contains("sprite") || folk.contains("moth") {
                let wing = UIColor.white.withAlphaComponent(0.55)
                shape(CGPath(ellipseIn: CGRect(x: 2, y: 26, width: 18, height: 26), transform: nil), wing)
                shape(CGPath(ellipseIn: CGRect(x: 28, y: 26, width: 18, height: 26), transform: nil), wing)
            }
            // Body (a rounded robe)
            shape(CGPath(roundedRect: CGRect(x: 13, y: 30, width: 22, height: 36), cornerWidth: 9, cornerHeight: 9, transform: nil), color)
            // Head
            let headColor = folk.contains("human") || folk.contains("elf") || folk.contains("witch") || folk.contains("knight")
                ? UIColor(hex: "#F0D2B0") : color.adjusted(by: 0.15)
            if folk.contains("-folk") || folk.contains("folk ") {
                // Ears
                shape(CGPath(ellipseIn: CGRect(x: 11, y: 6, width: 10, height: 14), transform: nil), headColor)
                shape(CGPath(ellipseIn: CGRect(x: 27, y: 6, width: 10, height: 14), transform: nil), headColor)
            }
            if folk.contains("elf") {
                let ear = CGMutablePath()
                ear.addLines(between: [CGPoint(x: 12, y: 20), CGPoint(x: 4, y: 12), CGPoint(x: 14, y: 16)])
                ear.closeSubpath()
                ear.addLines(between: [CGPoint(x: 36, y: 20), CGPoint(x: 44, y: 12), CGPoint(x: 34, y: 16)])
                ear.closeSubpath()
                shape(ear, headColor)
            }
            shape(CGPath(ellipseIn: CGRect(x: 12, y: 10, width: 24, height: 24), transform: nil), headColor)
            // Eyes
            g.setFillColor(ink.cgColor)
            g.fillEllipse(in: CGRect(x: 18, y: 19, width: 3.5, height: 3.5))
            g.fillEllipse(in: CGRect(x: 26.5, y: 19, width: 3.5, height: 3.5))
            // Witches get a hat
            if folk.contains("witch") {
                let hat = CGMutablePath()
                hat.addLines(between: [CGPoint(x: 8, y: 14), CGPoint(x: 40, y: 14), CGPoint(x: 26, y: 0)])
                hat.closeSubpath()
                shape(hat, UIColor(hex: "#3A2F4A"))
            }
        }
    }

    /// Simple drawn decorations, picked by the `shape` field in buildings.json.
    static func decoration(_ def: BuildingDef) -> UIImage {
        let n = CGFloat(def.size)
        let w = IsoMath.tileWidth * n, footH = IsoMath.tileHeight * n
        let shape = def.shape ?? "statue"
        let extra: CGFloat = switch shape {
        case "lamp": 110
        case "tree": 130
        case "statue": 90
        case "fountain": 60
        case "flowers": 16
        default: 0
        }
        let canvas = CGSize(width: w, height: footH + extra)
        let color = UIColor(hex: def.color)
        let ink = UIColor(hex: "#1D1A24")

        return UIGraphicsImageRenderer(size: canvas).image { ctx in
            let g = ctx.cgContext
            let cx = w / 2, cy = canvas.height - footH / 2
            g.setLineWidth(2)
            g.setLineJoin(.round)
            g.setStrokeColor(ink.cgColor)

            func diamond(scale: CGFloat, lift: CGFloat = 0) -> CGPath {
                let hw = w / 2 * scale, hh = footH / 2 * scale
                let p = CGMutablePath()
                p.addLines(between: [CGPoint(x: cx, y: cy - hh - lift), CGPoint(x: cx + hw, y: cy - lift),
                                     CGPoint(x: cx, y: cy + hh - lift), CGPoint(x: cx - hw, y: cy - lift)])
                p.closeSubpath()
                return p
            }
            func fillPath(_ path: CGPath, _ c: UIColor, stroke: Bool = true) {
                g.addPath(path)
                g.setFillColor(c.cgColor)
                g.drawPath(using: stroke ? .fillStroke : .fill)
            }
            func ellipse(_ r: CGRect, _ c: UIColor, stroke: Bool = true) {
                fillPath(CGPath(ellipseIn: r, transform: nil), c, stroke: stroke)
            }

            switch shape {
            case "path":
                fillPath(diamond(scale: 0.96), color)
                g.setStrokeColor(color.adjusted(by: -0.2).cgColor)
                for i in 1..<4 {
                    let t = CGFloat(i) / 4
                    g.move(to: CGPoint(x: cx - w / 2 * 0.96 * (1 - t), y: cy - footH / 2 * 0.96 * t))
                    g.addLine(to: CGPoint(x: cx + w / 2 * 0.96 * t, y: cy + footH / 2 * 0.96 * (1 - t)))
                }
                g.strokePath()
            case "flowers":
                fillPath(diamond(scale: 0.7), UIColor(hex: "#4E7A3E"), stroke: false)
                for (dx, dy) in [(-22.0, -4.0), (8.0, -12.0), (20.0, 4.0), (-6.0, 8.0), (-30.0, 6.0), (30.0, -6.0)] {
                    ellipse(CGRect(x: cx + dx - 7, y: cy + dy - 7 - 8, width: 14, height: 14), color)
                    ellipse(CGRect(x: cx + dx - 2.5, y: cy + dy - 2.5 - 8, width: 5, height: 5), UIColor(hex: "#8A5B00"), stroke: false)
                }
            case "lamp":
                fillPath(diamond(scale: 0.3), UIColor(hex: "#6B5A48"))
                g.addRect(CGRect(x: cx - 4, y: cy - extra + 12, width: 8, height: extra - 12))
                g.setFillColor(UIColor(hex: "#3A2F28").cgColor)
                g.drawPath(using: .fillStroke)
                let glow = CGRect(x: cx - 26, y: cy - extra - 18, width: 52, height: 52)
                ellipse(glow, color.withAlphaComponent(0.25), stroke: false)
                ellipse(glow.insetBy(dx: 12, dy: 12), color)
            case "tree":
                fillPath(diamond(scale: 0.55), UIColor(hex: "#3E5A34"), stroke: false)
                g.addRect(CGRect(x: cx - 7, y: cy - 60, width: 14, height: 60))
                g.setFillColor(UIColor(hex: "#5A4632").cgColor)
                g.drawPath(using: .fillStroke)
                ellipse(CGRect(x: cx - 52, y: cy - extra - 20, width: 104, height: 100), color.adjusted(by: -0.1))
                ellipse(CGRect(x: cx - 38, y: cy - extra - 26, width: 70, height: 66), color.adjusted(by: 0.08))
            case "statue":
                fillPath(diamond(scale: 0.5), UIColor(hex: "#6E7A74"))
                g.addRect(CGRect(x: cx - 20, y: cy - 40, width: 40, height: 36))
                g.setFillColor(UIColor(hex: "#7F8C86").cgColor)
                g.drawPath(using: .fillStroke)
                ellipse(CGRect(x: cx - 22, y: cy - 78, width: 44, height: 40), color)
                ellipse(CGRect(x: cx - 16, y: cy - 86, width: 12, height: 12), color.adjusted(by: 0.1))
                ellipse(CGRect(x: cx + 4, y: cy - 86, width: 12, height: 12), color.adjusted(by: 0.1))
            case "pond", "fountain":
                fillPath(diamond(scale: 0.92), UIColor(hex: "#8A8F80"))
                fillPath(diamond(scale: 0.75), color, stroke: false)
                if shape == "pond" {
                    for (dx, dy) in [(-30.0, -6.0), (24.0, 10.0), (10.0, -20.0)] {
                        ellipse(CGRect(x: cx + dx - 12, y: cy + dy - 6, width: 24, height: 12), UIColor(hex: "#6E9A5A"))
                    }
                } else {
                    g.addRect(CGRect(x: cx - 8, y: cy - extra + 10, width: 16, height: extra - 10))
                    g.setFillColor(UIColor(hex: "#9AA39A").cgColor)
                    g.drawPath(using: .fillStroke)
                    let spray = CGRect(x: cx - 30, y: cy - extra - 16, width: 60, height: 40)
                    ellipse(spray, color.withAlphaComponent(0.35), stroke: false)
                    ellipse(spray.insetBy(dx: 16, dy: 10), UIColor.white.withAlphaComponent(0.8), stroke: false)
                }
            default:
                fillPath(diamond(scale: 0.6), color)
            }
        }
    }

    /// An isometric block with walls, a pyramid roof in the building's colour, a door and a lit window.
    /// Houses are lower, the shrine and guild have tall spires, so kinds are easy to tell apart.
    /// Later stages are taller, fly a pennant and have more lit windows.
    static func building(_ def: BuildingDef, stage: Int = 1) -> UIImage {
        let grow = 1 + 0.22 * CGFloat(max(0, stage - 1))
        let n = CGFloat(def.size)
        let w = IsoMath.tileWidth * n, footH = IsoMath.tileHeight * n
        let (wallScale, roofScale): (CGFloat, CGFloat) = switch def.kind {
        case .shop: (1, 1)
        case .house: (0.75, 1.15)
        case .shrine: (0.7, 2.2)
        case .guild: (1.3, 1.6)
        case .decoration: (0.5, 0.5)
        }
        let wallH: CGFloat = (30 + 18 * n) * wallScale * grow
        let roofH: CGFloat = (26 + 16 * n) * roofScale * grow
        let flagH: CGFloat = stage >= 2 ? 30 : 0
        let canvas = CGSize(width: w, height: footH + wallH + roofH + flagH)
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

            if stage >= 3 {
                // Extra windows.
                fill([onRight(0.12, 0.35), onRight(0.28, 0.35), onRight(0.28, 0.7), onRight(0.12, 0.7)],
                     UIColor(hex: "#FFD978"))
                fill([onRight(0.72, 0.35), onRight(0.88, 0.35), onRight(0.88, 0.7), onRight(0.72, 0.7)],
                     UIColor(hex: "#FFD978"))
                fill([onLeft(0.15, 0.4), onLeft(0.3, 0.4), onLeft(0.3, 0.72), onLeft(0.15, 0.72)],
                     UIColor(hex: "#FFD978"))
            }
            if stage >= 2 {
                // A pennant on the roof.
                g.setStrokeColor(UIColor(hex: "#1D1A24").cgColor)
                g.setLineWidth(2.5)
                g.move(to: apex)
                g.addLine(to: CGPoint(x: apex.x, y: apex.y - flagH))
                g.strokePath()
                fill([CGPoint(x: apex.x, y: apex.y - flagH), CGPoint(x: apex.x + 22, y: apex.y - flagH + 7),
                      CGPoint(x: apex.x, y: apex.y - flagH + 14)], stage >= 3 ? UIColor(hex: "#F2B544") : roof)
            }
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
