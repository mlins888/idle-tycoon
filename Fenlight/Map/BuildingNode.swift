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
