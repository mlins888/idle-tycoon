import SpriteKit
import UIKit

/// The isometric town map. Draws the ground, murk and buildings from `Game`,
/// and turns pans, pinches and taps into camera moves and game actions.
@MainActor
final class TownScene: SKScene {
    let game: Game
    let ui: MapInteraction

    private let cam = SKCameraNode()
    private let groundLayer = SKNode()
    private let buildingLayer = SKNode()
    private let overlayLayer = SKNode()

    private var tileNodes: [Tile: SKSpriteNode] = [:]
    private lazy var townsfolk = TownsfolkLayer(parent: buildingLayer)
    private var buildingNodes: [Int: BuildingNode] = [:]
    private var lastRevision = -1
    private var lastRestoration = -1.0
    private var lastBubbleRefresh: TimeInterval = 0
    private var lastTick: TimeInterval = 0
    private var didSetUp = false

    private let ghost = SKSpriteNode()
    private var ghostDefId: String?
    private let footprintOutline = SKShapeNode()
    private let chunkOutline = SKShapeNode()
    /// The reach of a decoration's aura, shown while placing or when one is selected.
    private let auraOutline = SKShapeNode()

    // Colours the fen moves between as it's restored.
    private let gloomSky = UIColor(hex: "#151C1A")
    private let restoredSky = UIColor(hex: "#24414F")
    private let gloomTint = UIColor(hex: "#5E6A55")

    init(game: Game, ui: MapInteraction) {
        self.game = game
        self.ui = ui
        super.init(size: CGSize(width: 390, height: 844))
        scaleMode = .resizeFill
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func didMove(to view: SKView) {
        if !didSetUp { setUp() }
        view.ignoresSiblingOrder = true
        if view.gestureRecognizers?.isEmpty ?? true {
            view.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePan)))
            view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(handlePinch)))
            view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap)))
        }
    }

    private func setUp() {
        didSetUp = true
        camera = cam
        addChild(cam)
        cam.position = IsoMath.center(of: Tile(c: 12, r: 12))
        cam.setScale(1.1)

        groundLayer.zPosition = 0
        buildingLayer.zPosition = 10
        overlayLayer.zPosition = 5000
        addChild(groundLayer)
        addChild(buildingLayer)
        addChild(overlayLayer)

        for c in 0..<World.size {
            for r in 0..<World.size {
                let tile = Tile(c: c, r: r)
                let node = SKSpriteNode(texture: ArtCatalog.shared.grassTile())
                node.position = IsoMath.center(of: tile)
                node.zPosition = CGFloat(c + r) * 0.001
                groundLayer.addChild(node)
                tileNodes[tile] = node
            }
        }

        chunkOutline.lineWidth = 3
        chunkOutline.strokeColor = UIColor(hex: "#F2B544")
        chunkOutline.fillColor = UIColor(hex: "#F2B544").withAlphaComponent(0.12)
        chunkOutline.glowWidth = 2
        chunkOutline.isHidden = true
        overlayLayer.addChild(chunkOutline)

        auraOutline.lineWidth = 2
        auraOutline.strokeColor = UIColor(hex: "#7FE3D6")
        auraOutline.fillColor = UIColor(hex: "#7FE3D6").withAlphaComponent(0.1)
        auraOutline.isHidden = true
        overlayLayer.addChild(auraOutline)

        footprintOutline.lineWidth = 2
        footprintOutline.zPosition = 1
        footprintOutline.isHidden = true
        overlayLayer.addChild(footprintOutline)

        ghost.anchorPoint = CGPoint(x: 0.5, y: 0)
        ghost.alpha = 0.7
        ghost.colorBlendFactor = 0.45
        ghost.zPosition = 2
        ghost.isHidden = true
        overlayLayer.addChild(ghost)
    }

    // MARK: - Frame updates

    override func update(_ currentTime: TimeInterval) {
        if game.layoutRevision != lastRevision {
            lastRevision = game.layoutRevision
            syncLayout()
        }
        if game.restoration != lastRestoration {
            lastRestoration = game.restoration
            applyRestorationTint()
        }
        if currentTime - lastBubbleRefresh > 0.25 {
            lastBubbleRefresh = currentTime
            refreshBubbles()
        }
        townsfolk.update(currentTime)
        townsfolk.setSelected(ui.selectedResidentId)
        if currentTime - lastTick > 1 {
            lastTick = currentTime
            game.tick()
        }
        updatePlacementOverlay()
        updateChunkOutline()
        updateAuraOutline()
    }

    private func syncLayout() {
        let grass = ArtCatalog.shared.grassTile(), murk = ArtCatalog.shared.murkTile()
        for (tile, node) in tileNodes {
            node.texture = game.isCleansed(tile) ? grass : murk
        }

        let current = Set(game.state.buildings.map(\.id))
        for (id, node) in buildingNodes where !current.contains(id) {
            node.removeFromParent()
            buildingNodes[id] = nil
        }
        for b in game.state.buildings {
            guard let def = game.def(for: b) else { continue }
            let texture = ArtCatalog.shared.building(def, stage: b.stage)
            let node = buildingNodes[b.id] ?? {
                let n = BuildingNode(buildingId: b.id, texture: texture)
                buildingLayer.addChild(n)
                buildingNodes[b.id] = n
                return n
            }()
            node.setTexture(texture)
            node.position = IsoMath.anchor(origin: b.origin, size: def.size)
            node.zPosition = IsoMath.zPosition(origin: b.origin, size: def.size)
            node.showWorkers(colors: game.workers(at: b.id).map(\.color), keeper: game.isAuto(b))
        }
        applyRestorationTint()
        townsfolk.sync(game)
    }

    /// The fen starts grey and gloomy and gains colour as more of it is cleansed.
    private func applyRestorationTint() {
        let gloom = CGFloat(max(0, 1 - game.restoration * 1.6))
        backgroundColor = gloomSky.blended(with: restoredSky, CGFloat(game.restoration))
        for (tile, node) in tileNodes where game.isCleansed(tile) {
            node.color = gloomTint
            node.colorBlendFactor = gloom * 0.65
        }
        for (tile, node) in tileNodes where !game.isCleansed(tile) {
            node.colorBlendFactor = 0
        }
    }

    private func refreshBubbles() {
        for b in game.state.buildings {
            guard let node = buildingNodes[b.id] else { continue }
            node.showPending(game.pending(b), capacity: game.capacity(b), full: game.isFull(b))
            node.showRenovation(remaining: game.renovationRemaining(b))
        }
    }

    private func updatePlacementOverlay() {
        let defId: String?
        var movingId: Int?
        switch ui.mode {
        case .browse:
            defId = nil
        case .placing(let id):
            defId = id
        case .moving(let id):
            movingId = id
            defId = game.building(id: id)?.defId
        }

        for (id, node) in buildingNodes { node.alpha = id == movingId ? 0.25 : 1 }

        guard let defId, let def = game.content.building(defId) else {
            ghost.isHidden = true
            footprintOutline.isHidden = true
            ghostDefId = nil
            return
        }
        if ui.ghostOrigin == nil {
            ui.ghostOrigin = World.origin(centeredOn: IsoMath.tile(at: cam.position), size: def.size)
        }
        guard let origin = ui.ghostOrigin else { return }

        if ghostDefId != defId {
            ghostDefId = defId
            ghost.texture = ArtCatalog.shared.building(def)
            ghost.size = ghost.texture?.size() ?? .zero
        }
        let ok = game.canPlace(defId, at: origin, ignoring: movingId)
        let color = ok ? UIColor(hex: "#7FD17A") : UIColor(hex: "#E0654A")
        ghost.isHidden = false
        ghost.color = color
        ghost.position = IsoMath.anchor(origin: origin, size: def.size)
        ghost.zPosition = 2
        footprintOutline.isHidden = false
        footprintOutline.path = IsoMath.diamondPath(origin: origin, size: def.size)
        footprintOutline.strokeColor = color
        footprintOutline.fillColor = color.withAlphaComponent(0.25)
    }

    /// Outlines the area a decoration's aura reaches: while placing or moving one, or while one is selected.
    private func updateAuraOutline() {
        var shown: (def: BuildingDef, origin: Tile)?
        switch ui.mode {
        case .placing(let defId):
            if let def = game.content.building(defId), let origin = ui.ghostOrigin { shown = (def, origin) }
        case .moving(let id):
            if let b = game.building(id: id), let def = game.def(for: b), let origin = ui.ghostOrigin { shown = (def, origin) }
        case .browse:
            if let id = ui.selectedBuildingId, let b = game.building(id: id), let def = game.def(for: b) {
                shown = (def, b.origin)
            }
        }
        guard let (def, origin) = shown, let aura = def.aura else {
            auraOutline.isHidden = true
            return
        }
        auraOutline.isHidden = false
        let r = aura.radius
        auraOutline.path = IsoMath.diamondPath(origin: Tile(c: origin.c - r, r: origin.r - r), size: def.size + 2 * r)
    }

    private func updateChunkOutline() {
        guard let chunk = ui.selectedChunk else {
            chunkOutline.isHidden = true
            return
        }
        chunkOutline.isHidden = false
        chunkOutline.path = IsoMath.diamondPath(origin: World.origin(of: chunk), size: World.chunkSize)
    }

    // MARK: - Gestures

    @objc private func handlePan(_ g: UIPanGestureRecognizer) {
        guard let view = g.view else { return }
        let t = g.translation(in: view)
        cam.position.x -= t.x * cam.xScale
        cam.position.y += t.y * cam.yScale
        g.setTranslation(.zero, in: view)
        clampCamera()
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        let scale = min(2.2, max(0.45, cam.xScale / g.scale))
        cam.setScale(scale)
        g.scale = 1
        clampCamera()
    }

    private func clampCamera() {
        let halfW = CGFloat(World.size) * IsoMath.tileWidth / 2
        let fullH = CGFloat(World.size) * IsoMath.tileHeight
        cam.position.x = min(halfW, max(-halfW, cam.position.x))
        cam.position.y = min(0, max(-fullH, cam.position.y))
    }

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard let view = g.view else { return }
        let point = convertPoint(fromView: g.location(in: view))
        let tile = IsoMath.tile(at: point)

        switch ui.mode {
        case .placing(let defId):
            if let def = game.content.building(defId) {
                ui.ghostOrigin = World.origin(centeredOn: tile, size: def.size)
            }
        case .moving(let id):
            if let b = game.building(id: id), let def = game.def(for: b) {
                ui.ghostOrigin = World.origin(centeredOn: tile, size: def.size)
            }
        case .browse:
            // Collecting wins over everything; then people; then buildings; then murk.
            let hitBuilding = buildingHit(at: point, tile: tile)
            if let id = hitBuilding, let node = buildingNodes[id] {
                let amount = game.collect(id)
                if amount >= 1 {
                    ui.clearSelection()
                    floatText("+\(Format.compact(amount))", above: node)
                    refreshBubbles()
                    Haptics.collect()
                    return
                }
            }
            if let residentId = townsfolk.resident(at: point) {
                ui.clearSelection()
                ui.selectedResidentId = residentId
                Haptics.collect()
            } else if let id = hitBuilding {
                ui.clearSelection()
                ui.selectedBuildingId = id
            } else if World.inBounds(tile), !game.isCleansed(tile) {
                ui.clearSelection()
                ui.selectedChunk = World.chunk(of: tile)
            } else {
                ui.clearSelection()
            }
        }
    }

    /// The building under a tap: first whatever stands on the tapped tile, then the frontmost sprite.
    private func buildingHit(at point: CGPoint, tile: Tile) -> Int? {
        let sprites = buildingNodes.values
            .filter { $0.tapFrame.contains(point) }
            .sorted { $0.zPosition > $1.zPosition }
        if let front = sprites.first { return front.buildingId }
        return game.occupant(at: tile)?.id
    }

    private func floatText(_ text: String, above node: BuildingNode) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Heavy")
        label.text = text
        label.fontSize = 22
        label.fontColor = UIColor(hex: "#FFD978")
        label.position = CGPoint(x: node.position.x, y: node.position.y + node.sprite.size.height + 10)
        label.zPosition = 10
        overlayLayer.addChild(label)
        label.run(.sequence([
            .group([.moveBy(x: 0, y: 60, duration: 0.9), .sequence([.wait(forDuration: 0.4), .fadeOut(withDuration: 0.5)])]),
            .removeFromParent(),
        ]))
    }

    /// Gives every building a little bounce (used by Collect all).
    func celebrateCollectAll(amount: Double) {
        guard amount >= 1 else { return }
        for node in buildingNodes.values {
            let pulse = SKAction.sequence([.scale(to: 1.08, duration: 0.1), .scale(to: 1, duration: 0.15)])
            node.run(pulse)
        }
        refreshBubbles()
    }
}
