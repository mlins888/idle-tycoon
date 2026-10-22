import SpriteKit

/// One building on the map: its sprite plus the glimmer bubble that appears when it's ready to collect.
@MainActor
final class BuildingNode: SKNode {
    let buildingId: Int
    let sprite: SKSpriteNode
    private let bubble = SKNode()
    private let bubbleBack = SKShapeNode()
    private let bubbleLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var shownText = ""
    private var shownFull = false
    private let badges = SKNode()
    private let keeperLantern = SKShapeNode(circleOfRadius: 8)
    private let scaffold = SKNode()
    private let scaffoldLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var shownTexture: SKTexture?

    init(buildingId: Int, texture: SKTexture) {
        self.buildingId = buildingId
        self.sprite = SKSpriteNode(texture: texture)
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0)
        addChild(sprite)

        bubble.position = CGPoint(x: 0, y: sprite.size.height + 14)
        bubble.zPosition = 1
        bubble.isHidden = true
        addChild(bubble)

        bubbleBack.fillColor = UIColor(hex: "#FFF8E6")
        bubbleBack.lineWidth = 2.5
        bubble.addChild(bubbleBack)

        let coin = SKShapeNode(circleOfRadius: 9)
        coin.name = "coin"
        coin.fillColor = UIColor(hex: "#F2B544")
        coin.strokeColor = UIColor(hex: "#8A5B00")
        coin.lineWidth = 1.5
        bubble.addChild(coin)

        bubbleLabel.fontSize = 15
        bubbleLabel.fontColor = UIColor(hex: "#2A1B00")
        bubbleLabel.verticalAlignmentMode = .center
        bubbleLabel.horizontalAlignmentMode = .left
        bubble.addChild(bubbleLabel)

        badges.position = CGPoint(x: -sprite.size.width * 0.3, y: sprite.size.height * 0.55)
        badges.zPosition = 1
        addChild(badges)

        keeperLantern.fillColor = UIColor(hex: "#FFD978")
        keeperLantern.strokeColor = UIColor(hex: "#8A5B00")
        keeperLantern.glowWidth = 6
        keeperLantern.position = CGPoint(x: 0, y: sprite.size.height + 12)
        keeperLantern.zPosition = 1
        keeperLantern.isHidden = true
        let flicker = SKAction.sequence([.fadeAlpha(to: 0.7, duration: 0.8), .fadeAlpha(to: 1, duration: 0.8)])
        keeperLantern.run(.repeatForever(flicker))
        addChild(keeperLantern)

        scaffold.zPosition = 2
        scaffold.isHidden = true
        addChild(scaffold)
        scaffoldLabel.fontSize = 15
        scaffoldLabel.fontColor = UIColor(hex: "#FFF8E6")
        scaffoldLabel.verticalAlignmentMode = .center

        shownTexture = texture
        layoutAroundSprite()
    }

    /// Swaps the picture (e.g. when a building reaches a new stage) and moves the bubble and badges to fit.
    func setTexture(_ texture: SKTexture) {
        guard texture !== shownTexture else { return }
        shownTexture = texture
        sprite.texture = texture
        sprite.size = texture.size()
        layoutAroundSprite()
    }

    private func layoutAroundSprite() {
        let w = sprite.size.width, h = sprite.size.height
        bubble.removeAction(forKey: "bob")
        shownFull = false
        bubble.position = CGPoint(x: 0, y: h + 14)
        badges.position = CGPoint(x: -w * 0.3, y: h * 0.55)
        keeperLantern.position = CGPoint(x: 0, y: h + 12)
        buildScaffold(width: w, height: h)
    }

    /// Placeholder scaffolding: a dark frame with crossed planks over the building.
    private func buildScaffold(width w: CGFloat, height h: CGFloat) {
        scaffold.removeAllChildren()
        let frame = CGRect(x: -w * 0.38, y: h * 0.08, width: w * 0.76, height: h * 0.8)
        let shade = SKShapeNode(rect: frame, cornerRadius: 6)
        shade.fillColor = UIColor(hex: "#1D1A24").withAlphaComponent(0.55)
        shade.strokeColor = UIColor(hex: "#B08850")
        shade.lineWidth = 4
        scaffold.addChild(shade)
        let planks = CGMutablePath()
        let steps = 3
        for i in 0...steps {
            let y = frame.minY + frame.height * CGFloat(i) / CGFloat(steps)
            planks.move(to: CGPoint(x: frame.minX, y: y))
            planks.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        planks.move(to: CGPoint(x: frame.minX, y: frame.minY))
        planks.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        planks.move(to: CGPoint(x: frame.maxX, y: frame.minY))
        planks.addLine(to: CGPoint(x: frame.minX, y: frame.maxY))
        let lines = SKShapeNode(path: planks)
        lines.strokeColor = UIColor(hex: "#B08850")
        lines.lineWidth = 3
        scaffold.addChild(lines)

        let tag = SKShapeNode(rect: CGRect(x: -44, y: -14, width: 88, height: 28), cornerRadius: 14)
        tag.fillColor = UIColor(hex: "#1D1A24")
        tag.strokeColor = UIColor(hex: "#F2B544")
        tag.lineWidth = 2
        tag.position = CGPoint(x: 0, y: frame.maxY + 18)
        scaffold.addChild(tag)
        scaffoldLabel.removeFromParent()
        scaffoldLabel.position = tag.position
        scaffold.addChild(scaffoldLabel)
    }

    /// Shows scaffolding and a countdown while renovating; hides it otherwise.
    func showRenovation(remaining: TimeInterval?) {
        scaffold.isHidden = remaining == nil
        if let remaining { scaffoldLabel.text = Format.duration(remaining) }
    }

    /// A small coloured dot per worker, plus a glowing lantern when a keeper collects automatically.
    func showWorkers(colors: [String], keeper: Bool) {
        badges.removeAllChildren()
        for (i, hex) in colors.enumerated() {
            let dot = SKShapeNode(circleOfRadius: 9)
            dot.fillColor = UIColor(hex: hex)
            dot.strokeColor = UIColor(hex: "#FFF8E6")
            dot.lineWidth = 2.5
            dot.position = CGPoint(x: CGFloat(i) * 14, y: 0)
            badges.addChild(dot)
        }
        keeperLantern.isHidden = !keeper
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// The bubble appears once a shop is at least a tenth full, and bobs when it's completely full.
    func showPending(_ amount: Double, capacity: Double, full: Bool) {
        let visible = amount >= max(1, capacity * 0.1)
        bubble.isHidden = !visible
        guard visible else { return }

        let text = Format.compact(amount)
        if text != shownText {
            shownText = text
            bubbleLabel.text = text
            let width = bubbleLabel.frame.width + 40
            bubbleBack.path = CGPath(roundedRect: CGRect(x: -width / 2, y: -15, width: width, height: 30),
                                     cornerWidth: 15, cornerHeight: 15, transform: nil)
            bubble.childNode(withName: "coin")?.position = CGPoint(x: -width / 2 + 16, y: 0)
            bubbleLabel.position = CGPoint(x: -width / 2 + 30, y: 0)
        }
        if full != shownFull {
            shownFull = full
            bubbleBack.strokeColor = full ? UIColor(hex: "#E0654A") : UIColor(hex: "#F2B544")
            bubble.removeAction(forKey: "bob")
            bubble.position.y = sprite.size.height + 14
            if full {
                let bob = SKAction.sequence([.moveBy(x: 0, y: 6, duration: 0.6), .moveBy(x: 0, y: -6, duration: 0.6)])
                bob.timingMode = .easeInEaseOut
                bubble.run(.repeatForever(bob), withKey: "bob")
            }
        }
    }

    /// Area that counts as tapping this building (the sprite, plus the bubble when it's showing).
    var tapFrame: CGRect {
        var frame = sprite.frame
        if !bubble.isHidden { frame = frame.union(bubble.calculateAccumulatedFrame()) }
        return frame.offsetBy(dx: position.x, dy: position.y)
    }
}
