import SpriteKit

/// Residents walking around the map. Each one hangs around their workplace (or their home if they
/// don't have a job), wanders to nearby spots, pauses, sometimes visits another shop, and now and then
/// says something in a speech bubble. All of this is only for show and never touches the saved game.
@MainActor
final class TownsfolkLayer {
    private let parent: SKNode
    private(set) var nodes: [String: ResidentNode] = [:]
    private var walkable: Set<Tile> = []
    private var shopAnchors: [(Tile, Int)] = []
    private var nextChatter: TimeInterval = 0
    private var lastTime: TimeInterval?

    static let walkSpeed: CGFloat = 55

    init(parent: SKNode) {
        self.parent = parent
    }

    /// Call when buildings, land or residents change.
    func sync(_ game: Game) {
        walkable = Walkways.walkable(game.state, game.content)
        shopAnchors = game.state.buildings.compactMap { b in
            guard let def = game.def(for: b), def.kind == .shop else { return nil }
            return (b.origin, def.size)
        }

        let ids = Set(game.state.residents.map(\.defId))
        for (id, node) in nodes where !ids.contains(id) {
            node.removeFromParent()
            nodes[id] = nil
        }
        for resident in game.state.residents {
            guard let def = game.content.resident(resident.defId) else { continue }
            let anchorId = resident.workId ?? resident.homeId
            let anchor = game.building(id: anchorId).flatMap { b in game.def(for: b).map { (b.origin, $0.size) } }
            let node = nodes[def.id] ?? {
                let n = ResidentNode(def: def, texture: ArtCatalog.shared.walker(def))
                parent.addChild(n)
                nodes[def.id] = n
                if let anchor, let start = Walkways.around(anchor.0, size: anchor.1, radius: 2, in: walkable).randomElement() {
                    n.position = IsoMath.center(of: start)
                } else if let any = walkable.randomElement() {
                    n.position = IsoMath.center(of: any)
                }
                n.waitUntil = 0
                return n
            }()
            node.anchor = anchor
            // A building may have just been placed on top of them, or a route may now be blocked.
            node.route = []
            if !walkable.contains(node.tile), let safe = Walkways.nearest(to: node.tile, in: walkable) {
                node.position = IsoMath.center(of: safe)
            }
            node.updateDepth()
        }
    }

    func update(_ currentTime: TimeInterval) {
        let dt = min(0.1, currentTime - (lastTime ?? currentTime))
        lastTime = currentTime
        for node in nodes.values {
            if node.route.isEmpty {
                node.setWalking(false)
                if currentTime >= node.waitUntil { chooseDestination(for: node, now: currentTime) }
            } else {
                node.setWalking(true)
                node.step(dt: dt, speed: Self.walkSpeed)
                if node.route.isEmpty { node.waitUntil = currentTime + Double.random(in: 2...7) }
            }
        }
        if currentTime >= nextChatter {
            nextChatter = currentTime + Double.random(in: 5...10)
            let idle = nodes.values.filter { $0.route.isEmpty && !$0.def.chatter.isEmpty && !$0.isTalking }
            if nodes.values.contains(where: \.isTalking) == false, let speaker = idle.randomElement(),
               let line = speaker.def.chatter.randomElement() {
                speaker.say(line)
            }
        }
    }

    /// Mostly wander near their own spot; sometimes visit a shop elsewhere in town.
    private func chooseDestination(for node: ResidentNode, now: TimeInterval) {
        let visiting = Double.random(in: 0..<1) < 0.2
        let anchor = visiting ? (shopAnchors.randomElement() ?? node.anchor) : node.anchor
        let candidates: [Tile]
        if let anchor {
            candidates = Walkways.around(anchor.0, size: anchor.1, radius: visiting ? 1 : 2, in: walkable)
        } else {
            candidates = Walkways.around(node.tile, size: 1, radius: 3, in: walkable)
        }
        guard let goal = candidates.randomElement(),
              let route = Walkways.path(from: node.tile, to: goal, walkable: walkable), !route.isEmpty else {
            node.waitUntil = now + Double.random(in: 2...5)
            return
        }
        node.route = route.map(IsoMath.center(of:))
    }

    /// The resident under a tap, frontmost first.
    func resident(at point: CGPoint) -> String? {
        nodes.values
            .filter { $0.tapFrame.contains(point) }
            .max { $0.zPosition < $1.zPosition }?
            .def.id
    }

    func setSelected(_ id: String?) {
        for (key, node) in nodes { node.setSelected(key == id) }
    }
}

/// One resident on the map.
@MainActor
final class ResidentNode: SKNode {
    let def: ResidentDef
    private let sprite: SKSpriteNode
    private let ring = SKShapeNode(ellipseOf: CGSize(width: 46, height: 22))
    private let bubble = SKNode()
    /// Where they hang around: a footprint origin and size.
    var anchor: (Tile, Int)?
    /// Points still to walk to, in order.
    var route: [CGPoint] = []
    var waitUntil: TimeInterval = 0
    private var walking = false
    private(set) var isTalking = false

    init(def: ResidentDef, texture: SKTexture) {
        self.def = def
        self.sprite = SKSpriteNode(texture: texture)
        super.init()
        sprite.anchorPoint = CGPoint(x: 0.5, y: 0.08)
        addChild(sprite)

        ring.strokeColor = UIColor(hex: "#F2B544")
        ring.lineWidth = 3
        ring.glowWidth = 2
        ring.zPosition = -1
        ring.isHidden = true
        addChild(ring)

        bubble.zPosition = 1
        bubble.isHidden = true
        addChild(bubble)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    var tile: Tile { IsoMath.tile(at: position) }

    var tapFrame: CGRect {
        sprite.frame.insetBy(dx: -10, dy: -10).offsetBy(dx: position.x, dy: position.y)
    }

    /// Draw in front of things further up the screen and behind things further down.
    func updateDepth() {
        zPosition = 10.5 + (-position.y) / (IsoMath.tileHeight / 2)
    }

    func step(dt: TimeInterval, speed: CGFloat) {
        guard let target = route.first else { return }
        let dx = target.x - position.x, dy = target.y - position.y
        let dist = hypot(dx, dy)
        let move = speed * CGFloat(dt)
        if dist <= move {
            position = target
            route.removeFirst()
        } else {
            position.x += dx / dist * move
            position.y += dy / dist * move
        }
        if abs(dx) > 0.5 { sprite.xScale = dx < 0 ? -1 : 1 }
        updateDepth()
    }

    func setWalking(_ on: Bool) {
        guard on != walking else { return }
        walking = on
        if on {
            let hop = SKAction.sequence([.moveBy(x: 0, y: 4, duration: 0.14), .moveBy(x: 0, y: -4, duration: 0.14)])
            sprite.run(.repeatForever(hop), withKey: "walk")
        } else {
            sprite.removeAction(forKey: "walk")
            sprite.position = .zero
        }
    }

    func setSelected(_ selected: Bool) {
        ring.isHidden = !selected
    }

    func say(_ line: String) {
        bubble.removeAllChildren()
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.text = line
        label.fontSize = 13
        label.fontColor = UIColor(hex: "#2A1B00")
        label.verticalAlignmentMode = .center
        let w = label.frame.width + 20
        let back = SKShapeNode(rect: CGRect(x: -w / 2, y: -13, width: w, height: 26), cornerRadius: 13)
        back.fillColor = UIColor(hex: "#FFF8E6")
        back.strokeColor = UIColor(hex: def.color)
        back.lineWidth = 2
        bubble.addChild(back)
        bubble.addChild(label)
        bubble.position = CGPoint(x: 0, y: sprite.size.height + 18)
        bubble.alpha = 0
        bubble.isHidden = false
        isTalking = true
        bubble.run(.sequence([
            .fadeIn(withDuration: 0.2), .wait(forDuration: 3.5), .fadeOut(withDuration: 0.3),
            .run { [weak self] in
                self?.bubble.isHidden = true
                self?.isTalking = false
            },
        ]))
    }
}
