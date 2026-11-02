import SpriteKit

/// A lightweight isometric room. Static room geometry stays in SpriteKit; only visible app
/// records receive a character and an assigned workstation.
final class OfficeScene: SKScene {
    private let room = SKNode()
    private let departures = SKNode()
    private let isoDesk = SKTexture(imageNamed: "IsoDesk")
    private let isoChair = SKTexture(imageNamed: "IsoChair")
    private let isoMonitor = SKTexture(imageNamed: "IsoMonitor")
    private let isoKeyboard = SKTexture(imageNamed: "IsoKeyboard")
    private let isoLamp = SKTexture(imageNamed: "IsoLamp")
    private let isoBookshelf = SKTexture(imageNamed: "IsoBookshelf")
    private let isoPlant = SKTexture(imageNamed: "IsoPlant")
    private let isoPrinter = SKTexture(imageNamed: "IsoPrinter")
    private var radialGlow: SKTexture?
    private let characterSheets: [SKTexture] = (0..<6).map { SKTexture(imageNamed: "char_\($0)") }
    private var characterNodes: [String: SKSpriteNode] = [:]
    private var records: [ProcessRecord] = []
    private var selectedDevice: String?
    private var lastLayoutSize: CGSize = .zero
    private var newArrivalKeys: Set<String> = []

    private struct RoomGeometry {
        let center: CGPoint
        let halfWidth: CGFloat
        let halfHeight: CGFloat
        let wallHeight: CGFloat
        let furnitureScale: CGFloat

        init(_ size: CGSize) {
            center = CGPoint(x: size.width / 2, y: size.height * 0.415)
            halfWidth = size.width * 0.45
            halfHeight = size.height * 0.405
            wallHeight = size.height * 0.16
            furnitureScale = min(1, halfWidth / 560, halfHeight / 225)
        }

        var back: CGPoint { CGPoint(x: center.x, y: center.y + halfHeight) }
        var left: CGPoint { CGPoint(x: center.x - halfWidth, y: center.y) }
        var right: CGPoint { CGPoint(x: center.x + halfWidth, y: center.y) }
        var front: CGPoint { CGPoint(x: center.x, y: center.y - halfHeight) }

        func point(u: CGFloat, v: CGFloat) -> CGPoint {
            CGPoint(x: back.x + u * (left.x - back.x) + v * (right.x - back.x),
                    y: back.y + u * (left.y - back.y) + v * (right.y - back.y))
        }
    }

    /// Geometry is authored around a shared desk origin. Keeping these anchors together
    /// prevents the chair, sitter and keyboard drifting independently during layout edits.
    private struct WorkstationAnchors {
        let desk: CGPoint
        let chair: CGPoint
        let sitter: CGPoint
        let monitor: CGPoint
        let keyboard: CGPoint
        let facingRight: Bool

        init(center: CGPoint, facingRight: Bool, scale: CGFloat) {
            let direction: CGFloat = facingRight ? 1 : -1
            self.facingRight = facingRight
            desk = CGPoint(x: center.x, y: center.y - 5 * scale)
            chair = CGPoint(x: center.x - direction * 37 * scale, y: center.y - 29 * scale)
            keyboard = CGPoint(x: center.x + direction * 12 * scale, y: center.y + 3 * scale)
            monitor = CGPoint(x: center.x + direction * 23 * scale, y: center.y + 30 * scale)
            sitter = CGPoint(x: chair.x + direction * 9 * scale, y: chair.y + 29 * scale)
        }
    }

    override func didMove(to view: SKView) {
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.055, green: 0.075, blue: 0.11, alpha: 1)
        [isoDesk, isoChair, isoMonitor, isoKeyboard, isoLamp, isoBookshelf, isoPlant, isoPrinter].forEach {
            $0.filteringMode = .nearest
            $0.usesMipmaps = false
        }
        radialGlow = Self.makeRadialGlow()
        characterSheets.forEach { $0.filteringMode = .nearest; $0.usesMipmaps = false }
        addChild(departures)
        addChild(room)
        layoutRoom()
    }

    func render(_ records: [ProcessRecord], device: String?) {
        let oldKeys = Set(self.records.map(actorKey))
        let newKeys = Set(records.map(actorKey))
        let visualChanged = visualSignature(self.records, device: selectedDevice) != visualSignature(records, device: device)
        // Preserve real departures long enough to walk off screen before rebuilding the room.
        for key in oldKeys.subtracting(newKeys) {
            guard let actor = characterNodes.removeValue(forKey: key) else { continue }
            actor.move(toParent: departures)
            actor.removeAllActions()
            let walk = walkingFrames(characterIndex: stableIndex(for: key, count: characterSheets.count))
            let walkCycle = SKAction.repeat(.animate(with: walk, timePerFrame: 0.16), count: 2)
            actor.run(.sequence([.group([walkCycle, .moveBy(x: -size.width * 0.22, y: -size.height * 0.12, duration: 0.9), .fadeOut(withDuration: 0.9)]), .removeFromParent()]))
        }
        self.records = records
        selectedDevice = device
        newArrivalKeys = newKeys.subtracting(oldKeys)
        if view != nil && visualChanged { layoutRoom(animateArrivals: true) }
        newArrivalKeys.removeAll()
    }

    override func didChangeSize(_ oldSize: CGSize) { layoutRoom(animateArrivals: false) }

    private func layoutRoom(animateArrivals: Bool = false) {
        let oldSize = lastLayoutSize
        lastLayoutSize = size
        if oldSize != .zero && oldSize != size { characterNodes.removeAll() }
        room.removeAllChildren()
        guard size.width > 0, size.height > 0 else { return }
        drawRoomShell()
        drawFloor()
        drawDecor()
        drawWorkstations(animateArrivals: animateArrivals)
        drawHeader()
    }

    private func drawRoomShell() {
        let g = RoomGeometry(size)
        let raised = { (point: CGPoint) in CGPoint(x: point.x, y: point.y + g.wallHeight) }
        let leftWall = polygon([g.left, g.back, raised(g.back), raised(g.left)], fill: rgb(0x292333), stroke: rgb(0x5A4050), width: 3)
        let rightWall = polygon([g.back, g.right, raised(g.right), raised(g.back)], fill: rgb(0x33283B), stroke: rgb(0x634853), width: 3)
        leftWall.zPosition = 2; rightWall.zPosition = 2
        room.addChild(leftWall); room.addChild(rightWall)

        // Windows are projected onto the sloping wall, sharing its base edge.
        for (start, end) in [(0.17, 0.32), (0.48, 0.63)] {
            let p = interpolate(g.left, g.back, CGFloat(start))
            let q = interpolate(g.left, g.back, CGFloat(end))
            let bottom = g.wallHeight * 0.18, top = g.wallHeight * 0.86
            let frame = polygon([
                CGPoint(x: p.x, y: p.y + bottom), CGPoint(x: q.x, y: q.y + bottom),
                CGPoint(x: q.x, y: q.y + top), CGPoint(x: p.x, y: p.y + top)
            ], fill: rgb(0x9C643E), stroke: rgb(0x4B2D2B), width: 3)
            frame.zPosition = 3; room.addChild(frame)
            let glass = polygon([
                CGPoint(x: p.x + 5, y: p.y + bottom + 5), CGPoint(x: q.x - 5, y: q.y + bottom + 5),
                CGPoint(x: q.x - 5, y: q.y + top - 5), CGPoint(x: p.x + 5, y: p.y + top - 5)
            ], fill: rgb(0xFFE3A2), stroke: rgb(0xE6AF68), width: 1)
            glass.zPosition = 3.1; room.addChild(glass)
            let mullionX = (p.x + q.x) / 2
            let mullion = polygon([
                CGPoint(x: mullionX - 2, y: (p.y + q.y) / 2 + bottom + 4),
                CGPoint(x: mullionX + 2, y: (p.y + q.y) / 2 + bottom + 4),
                CGPoint(x: mullionX + 2, y: (p.y + q.y) / 2 + top - 4),
                CGPoint(x: mullionX - 2, y: (p.y + q.y) / 2 + top - 4)
            ], fill: rgb(0xA96D48), stroke: .clear, width: 0)
            mullion.zPosition = 3.2; room.addChild(mullion)
        }
        let boardBase = interpolate(g.back, g.right, 0.34)
        drawNoticeBoard(at: CGPoint(x: boardBase.x - 15, y: boardBase.y + g.wallHeight * 0.36), width: 135 * g.furnitureScale, height: 43 * g.furnitureScale)
    }

    private func drawFloor() {
        let g = RoomGeometry(size)
        let floor = polygon([g.back, g.right, g.front, g.left], fill: rgb(0xB87A43), stroke: rgb(0x4B2B25), width: 5)
        floor.zPosition = 1; room.addChild(floor)
        let divisions = 10
        for row in 0..<divisions {
            for col in 0..<divisions {
                let u0 = CGFloat(row) / CGFloat(divisions), u1 = CGFloat(row + 1) / CGFloat(divisions)
                let v0 = CGFloat(col) / CGFloat(divisions), v1 = CGFloat(col + 1) / CGFloat(divisions)
                let tile = polygon([g.point(u: u0, v: v0), g.point(u: u0, v: v1),
                                    g.point(u: u1, v: v1), g.point(u: u1, v: v0)],
                                   fill: rgb((row + col).isMultiple(of: 2) ? 0xE6B36D : 0xD49A57),
                                   stroke: rgb(0xAB7548), width: 1)
                tile.zPosition = 1.1; room.addChild(tile)
            }
        }
        let frontEdge = polygon([g.left, g.front, CGPoint(x: g.front.x, y: g.front.y - 8), CGPoint(x: g.left.x, y: g.left.y - 8)],
                                fill: rgb(0x60382D), stroke: .clear, width: 0)
        let rightEdge = polygon([g.front, g.right, CGPoint(x: g.right.x, y: g.right.y - 8), CGPoint(x: g.front.x, y: g.front.y - 8)],
                                fill: rgb(0x754332), stroke: .clear, width: 0)
        frontEdge.zPosition = 1.2; rightEdge.zPosition = 1.2
        room.addChild(frontEdge); room.addChild(rightEdge)
    }

    private func drawDecor() {
        let g = RoomGeometry(size), scale = g.furnitureScale
        for t in [CGFloat(0.24), CGFloat(0.55)] {
            let origin = interpolate(g.left, g.back, t)
            let beam = polygon([
                CGPoint(x: origin.x, y: origin.y + g.wallHeight * 0.18),
                CGPoint(x: origin.x + 36 * scale, y: origin.y + g.wallHeight * 0.28),
                CGPoint(x: origin.x + 195 * scale, y: origin.y - 87 * scale),
                CGPoint(x: origin.x + 125 * scale, y: origin.y - 112 * scale)
            ], fill: rgb(0xFFE19A).withAlphaComponent(0.06), stroke: .clear, width: 0)
            beam.zPosition = 2.4; room.addChild(beam)
            beam.run(.repeatForever(.sequence([.fadeAlpha(to: 0.025, duration: 2.8), .fadeAlpha(to: 0.06, duration: 3.2)])))
        }
        addAsset(isoPlant, at: CGPoint(x: g.center.x - g.halfWidth * 0.74, y: g.center.y + 25 * scale),
                 size: CGSize(width: 66 * scale, height: 75 * scale), z: 6)
        addAsset(isoPlant, at: CGPoint(x: g.center.x + g.halfWidth * 0.74, y: g.center.y + 25 * scale),
                 size: CGSize(width: 66 * scale, height: 75 * scale), z: 6)
        let shelfBase = interpolate(g.back, g.right, 0.77)
        addAsset(isoBookshelf, at: CGPoint(x: shelfBase.x - 14 * scale, y: shelfBase.y + 37 * scale),
                 size: CGSize(width: 76 * scale, height: 90 * scale), z: 6)
    }

    private func drawWorkstations(animateArrivals: Bool) {
        let g = RoomGeometry(size), scale = g.furnitureScale
        guard !records.isEmpty else {
            let empty = SKLabelNode(text: "办公室空闲 · 等待 App 启动")
            empty.fontName = "Menlo-Bold"; empty.fontSize = 13; empty.fontColor = rgb(0x5F4838)
            empty.position = g.center; empty.zPosition = 40; room.addChild(empty)
            return
        }
        // Four desks form one island. The facing direction changes across the central
        // aisle, so the office reads as paired furniture rather than a repeated icon grid.
        let visibleCount = min(records.count, 8)
        let islandCount = Int(ceil(Double(visibleCount) / 4))
        let islandCols = min(3, max(1, Int(ceil(sqrt(Double(islandCount) * 1.6)))))
        let islandRows = Int(ceil(Double(islandCount) / Double(islandCols)))
        let islandSpacingX = 270 * scale
        let islandSpacingY = 110 * scale
        let origin = g.center

        for (index, app) in records.prefix(visibleCount).enumerated() {
            let island = index / 4, seat = index % 4
            let islandRow = island / islandCols, islandCol = island % islandCols
            let islandX = origin.x + (CGFloat(islandCol) - CGFloat(islandCols - 1) / 2) * islandSpacingX
            let islandY = origin.y + (CGFloat(islandRows - 1) / 2 - CGFloat(islandRow)) * islandSpacingY
            let facingRight = seat.isMultiple(of: 2)
            let x = islandX + (facingRight ? -80 : 80) * scale
            let y = islandY + (seat < 2 ? 55 : -55) * scale
            let anchors = WorkstationAnchors(center: CGPoint(x: x, y: y), facingRight: facingRight, scale: scale)
            let depth = 10 + (size.height - y) * 0.05
            let shadow = SKShapeNode(ellipseOf: CGSize(width: 104 * scale, height: 19 * scale))
            shadow.position = CGPoint(x: x, y: y - 32 * scale)
            shadow.fillColor = rgb(0x5B3428).withAlphaComponent(0.25)
            shadow.strokeColor = .clear; shadow.zPosition = depth; room.addChild(shadow)

            addAsset(isoChair, at: anchors.chair, size: CGSize(width: 62 * scale, height: 62 * scale), z: depth + 1, flipX: !facingRight)
            drawDesk(at: anchors.desk, z: depth + 2, flipX: !facingRight, scale: scale)
            drawCharacter(app, at: anchors.sitter, z: depth + 3.5, animateArrival: animateArrivals && newArrivalKeys.contains(actorKey(app)), facingRight: facingRight, scale: scale)
            drawMonitor(at: anchors.monitor, active: app.isFrontmost, z: depth + 5, flipX: !facingRight, scale: scale)
            addAsset(isoKeyboard, at: anchors.keyboard, size: CGSize(width: 40 * scale, height: 40 * scale), z: depth + 5.5, flipX: !facingRight)
            drawDesktopDetails(at: anchors.desk, facingRight: facingRight, variant: index, z: depth + 5, scale: scale)
            if seat == 0 || (island == islandCount - 1 && seat == 2) {
                let lampPoint = CGPoint(x: anchors.desk.x + 34 * scale, y: anchors.desk.y + 36 * scale)
                addGlow(at: CGPoint(x: lampPoint.x, y: lampPoint.y - 7 * scale), size: CGSize(width: 104 * scale, height: 57 * scale), color: rgb(0xF8C96C), alpha: 0.28, z: depth + 4)
                addAsset(isoLamp, at: lampPoint, size: CGSize(width: 45 * scale, height: 45 * scale), z: depth + 6)
            }
            drawAppLabel(app, at: CGPoint(x: x, y: y + (seat < 2 ? 72 : -65) * scale), z: 80, scale: scale)
        }
        if records.count > visibleCount {
            let more = SKLabelNode(text: "+\(records.count - visibleCount) App · 见下方列表")
            more.fontName = "Menlo-Bold"; more.fontSize = 10; more.fontColor = rgb(0xF1D6A7)
            more.horizontalAlignmentMode = .right
            more.position = CGPoint(x: size.width - 17, y: size.height - 43)
            more.zPosition = 100; room.addChild(more)
        }
    }

    private func drawCharacter(_ app: ProcessRecord, at point: CGPoint, z: CGFloat, animateArrival: Bool, facingRight: Bool, scale: CGFloat) {
        let key = actorKey(app)
        let characterIndex = stableIndex(for: key, count: characterSheets.count)
        let workFrames = SeatedCharacterArt.frames(variant: characterIndex, facingRight: facingRight)
        let workFrame = workFrames[0]
        let actor = SKSpriteNode(texture: workFrame, size: CGSize(width: 56 * scale, height: 56 * scale))
        actor.position = point
        actor.zPosition = z
        actor.texture?.filteringMode = .nearest
        actor.name = "pixel-character-\(key)"
        room.addChild(actor)
        characterNodes[key] = actor

        if animateArrival {
            // A compact sit-down motion ends in the real seated typing loop.
            actor.position = CGPoint(x: point.x, y: point.y + 12 * scale)
            actor.yScale = 1.12
            actor.run(.sequence([.group([.move(to: point, duration: 0.28), .scaleY(to: 1, duration: 0.28)]), .run { [weak actor] in
                let work = SKAction.animate(with: workFrames, timePerFrame: 0.32, resize: false, restore: false)
                actor?.run(.repeatForever(work), withKey: "work")
            }]), withKey: "arrival")
        } else {
            let work = SKAction.animate(with: workFrames, timePerFrame: 0.32, resize: false, restore: false)
            actor.run(.repeatForever(work), withKey: "work")
        }
    }

    private func actorKey(_ app: ProcessRecord) -> String { "\(app.deviceID):\(app.id)" }

    private func visualSignature(_ records: [ProcessRecord], device: String?) -> String {
        let apps = records.map { "\(actorKey($0))|\($0.name)|\($0.department.rawValue)|\($0.isFrontmost)" }.sorted().joined(separator: ";")
        return "\(device ?? "all")|\(apps)"
    }

    private func stableIndex(for string: String, count: Int) -> Int {
        let hash = string.utf8.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 }
        return Int(hash % UInt32(max(1, count)))
    }

    /// Sprite sheets use 16×32 cells, seven columns and three rows. SpriteKit texture rects
    /// start at the lower-left, so convert the source's top-down row index here.
    private func frame(in sheet: SKTexture, column: Int, row: Int) -> SKTexture {
        let columns: CGFloat = 7, rows: CGFloat = 3
        let rect = CGRect(x: CGFloat(column) / columns, y: 1 - CGFloat(row + 1) / rows, width: 1 / columns, height: 1 / rows)
        let texture = SKTexture(rect: rect, in: sheet)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }

    private func walkingFrames(characterIndex: Int) -> [SKTexture] {
        let sheet = characterSheets[characterIndex % characterSheets.count]
        return [0, 1, 2, 1].map { frame(in: sheet, column: $0, row: 0) }
    }

    private func drawMonitor(at point: CGPoint, active: Bool, z: CGFloat, flipX: Bool, scale: CGFloat) {
        addGlow(at: CGPoint(x: point.x, y: point.y + 4 * scale), size: CGSize(width: 76 * scale, height: 42 * scale), color: rgb(active ? 0x72BFEA : 0xA9C5D0), alpha: active ? 0.38 : 0.10, z: z - 1)
        addAsset(isoMonitor, at: point, size: CGSize(width: 55 * scale, height: 55 * scale), z: z, flipX: flipX)
        let status = SKShapeNode(ellipseOf: CGSize(width: 4 * scale, height: 4 * scale))
        status.position = CGPoint(x: point.x + (flipX ? -17 : 17) * scale, y: point.y + 8 * scale)
        status.fillColor = rgb(active ? 0xA8E28B : 0x627B74)
        status.strokeColor = .clear
        status.zPosition = z + 1
        room.addChild(status)
    }

    private func drawDesk(at point: CGPoint, z: CGFloat, flipX: Bool, scale: CGFloat) {
        addAsset(isoDesk, at: point, size: CGSize(width: 115 * scale, height: 115 * scale), z: z, flipX: flipX)
    }

    private func drawDesktopDetails(at point: CGPoint, facingRight: Bool, variant: Int, z: CGFloat, scale: CGFloat) {
        let direction: CGFloat = facingRight ? 1 : -1
        let x = point.x - direction * 30 * scale
        let y = point.y + 20 * scale
        // A small stack of paper follows the isometric desktop plane.
        for layer in 0..<3 {
            let offset = CGFloat(layer) * 2 * scale
            let sheet = polygon([
                CGPoint(x: x - 12 * scale, y: y + offset), CGPoint(x: x + 2 * scale, y: y + 6 * scale + offset),
                CGPoint(x: x + 14 * scale, y: y + offset), CGPoint(x: x, y: y - 6 * scale + offset)
            ], fill: rgb(layer == 2 ? 0xFFF2D1 : 0xD6BD91), stroke: rgb(0x8A6746), width: 1)
            sheet.zPosition = z + CGFloat(layer) * 0.03
            room.addChild(sheet)
        }
        let ink = SKShapeNode(rectOf: CGSize(width: 8 * scale, height: max(1, scale)))
        ink.position = CGPoint(x: x, y: y + 4 * scale); ink.zRotation = -.pi / 8
        ink.fillColor = rgb(0x7F7565); ink.strokeColor = .clear; ink.zPosition = z + 0.2; room.addChild(ink)

        let bookX = point.x - direction * 38 * scale
        let bookY = point.y + 35 * scale
        for layer in 0..<2 {
            let offset = CGFloat(layer) * 5 * scale
            let cover = polygon([
                CGPoint(x: bookX - 10 * scale, y: bookY + offset), CGPoint(x: bookX + 1 * scale, y: bookY + 5 * scale + offset),
                CGPoint(x: bookX + 11 * scale, y: bookY + offset), CGPoint(x: bookX, y: bookY - 5 * scale + offset)
            ], fill: rgb((variant + layer).isMultiple(of: 2) ? 0x688B72 : 0xA85E4A), stroke: rgb(0x493B35), width: 1)
            cover.zPosition = z + 0.3 + CGFloat(layer) * 0.1; room.addChild(cover)
        }

        if variant.isMultiple(of: 3) {
            let potX = point.x + direction * 43 * scale
            let potY = point.y + 25 * scale
            let pot = polygon([
                CGPoint(x: potX - 6 * scale, y: potY), CGPoint(x: potX + 6 * scale, y: potY),
                CGPoint(x: potX + 4 * scale, y: potY - 8 * scale), CGPoint(x: potX - 4 * scale, y: potY - 8 * scale)
            ], fill: rgb(0xB46E4F), stroke: rgb(0x583C30), width: 1)
            pot.zPosition = z + 0.4; room.addChild(pot)
            for (dx, dy) in [(-5, 8), (0, 12), (5, 7), (0, 5)] {
                let leaf = SKShapeNode(rectOf: CGSize(width: 6 * scale, height: 5 * scale))
                leaf.position = CGPoint(x: potX + CGFloat(dx) * scale, y: potY + CGFloat(dy) * scale)
                leaf.fillColor = rgb(dx == 0 ? 0x4F8B59 : 0x6CA367)
                leaf.strokeColor = rgb(0x36523D); leaf.lineWidth = 1
                leaf.isAntialiased = false; leaf.zPosition = z + 0.5; room.addChild(leaf)
            }
        }
    }

    private func deskFace(_ points: [CGPoint], fill: SKColor, z: CGFloat) -> SKShapeNode {
        let face = polygon(points, fill: fill, stroke: rgb(0x673B2A), width: 2)
        face.zPosition = z
        return face
    }

    private func drawAppLabel(_ app: ProcessRecord, at point: CGPoint, z: CGFloat, scale: CGFloat) {
        let label = SKLabelNode(text: String(app.name.prefix(14)))
        label.fontName = "Menlo-Bold"; label.fontSize = max(7, 9 * scale); label.fontColor = rgb(0x342A2D)
        label.position = point; label.verticalAlignmentMode = .center; label.zPosition = z + 1
        let width = min(120 * scale, max(48 * scale, CGFloat(app.name.count) * 5.5 * scale + 16 * scale))
        let card = SKShapeNode(rectOf: CGSize(width: width, height: 18 * scale), cornerRadius: 4 * scale)
        card.position = point; card.fillColor = rgb(app.isFrontmost ? 0xFFF1C9 : 0xF4DDAF).withAlphaComponent(0.96)
        card.strokeColor = rgb(app.isFrontmost ? 0xC98847 : 0xB8885A); card.lineWidth = 1; card.zPosition = z; room.addChild(card); room.addChild(label)
        let department = SKShapeNode(rectOf: CGSize(width: 5 * scale, height: 11 * scale), cornerRadius: 1)
        department.position = CGPoint(x: point.x - width / 2 + 3 * scale, y: point.y); department.fillColor = rgb(app.department.colorHex); department.strokeColor = .clear; department.zPosition = z + 2; room.addChild(department)
        if app.isFrontmost {
            let bubble = SKLabelNode(text: "前台")
            bubble.fontName = "Menlo-Bold"; bubble.fontSize = max(6, 7 * scale); bubble.fontColor = rgb(0x855324); bubble.position = CGPoint(x: point.x, y: point.y + 14 * scale); bubble.zPosition = z + 2; room.addChild(bubble)
        }
    }

    private func drawBookshelf(at point: CGPoint, width: CGFloat, height: CGFloat) {
        addAsset(isoBookshelf, at: CGPoint(x: point.x + width / 2, y: point.y + height / 2), size: CGSize(width: width, height: height), z: 7)
    }

    private func addAsset(_ texture: SKTexture, at point: CGPoint, size: CGSize, z: CGFloat, flipX: Bool = false) {
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.position = point
        sprite.xScale = flipX ? -1 : 1
        sprite.zPosition = z
        sprite.texture?.filteringMode = .nearest
        room.addChild(sprite)
    }

    private func addGlow(at point: CGPoint, size: CGSize, color: SKColor, alpha: CGFloat, z: CGFloat) {
        guard let radialGlow else { return }
        let glow = SKSpriteNode(texture: radialGlow, size: size)
        glow.position = point
        glow.color = color
        glow.colorBlendFactor = 1
        glow.alpha = alpha
        glow.blendMode = .alpha
        glow.zPosition = z
        room.addChild(glow)
        let pulse = SKAction.sequence([
            .fadeAlpha(to: alpha * 0.62, duration: 1.6),
            .fadeAlpha(to: alpha, duration: 1.9)
        ])
        glow.run(.repeatForever(pulse))
    }

    private static func makeRadialGlow() -> SKTexture? {
        let side = 128
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
                CGColor(red: 1, green: 1, blue: 1, alpha: 0.88),
                CGColor(red: 1, green: 1, blue: 1, alpha: 0)
              ] as CFArray, locations: [0, 1]) else { return nil }
        let center = CGPoint(x: side / 2, y: side / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(side) / 2, options: [.drawsAfterEndLocation])
        guard let image = context.makeImage() else { return nil }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        texture.usesMipmaps = false
        return texture
    }

    private func drawNoticeBoard(at point: CGPoint, width: CGFloat, height: CGFloat) {
        addRect(CGRect(x: point.x, y: point.y, width: width, height: height), color: rgb(0xB77B4A), z: 6)
        addRect(CGRect(x: point.x + 4, y: point.y + 4, width: width - 8, height: height - 8), color: rgb(0xF0D8A4), z: 7)
        for i in 0..<4 {
            let bar = SKShapeNode(rectOf: CGSize(width: width * (0.22 + CGFloat(i % 2) * 0.13), height: 2))
            bar.position = CGPoint(x: point.x + width * 0.24, y: point.y + height * (0.25 + CGFloat(i) * 0.12))
            bar.fillColor = rgb(i.isMultiple(of: 2) ? 0xA36443 : 0x777E55); bar.strokeColor = .clear; bar.zPosition = 8; room.addChild(bar)
        }
        for i in 0..<3 {
            let bar = SKShapeNode(rectOf: CGSize(width: 4, height: height * CGFloat([0.3, 0.48, 0.38][i])))
            bar.position = CGPoint(x: point.x + width * (0.66 + CGFloat(i) * 0.08), y: point.y + height * 0.28)
            bar.fillColor = rgb([0xC67845, 0xD1A347, 0x758C62][i]); bar.strokeColor = .clear; bar.zPosition = 8; room.addChild(bar)
        }
    }

    private func drawHeader() {
        let title = SKLabelNode(text: "PIXEL WORKSPACE  /  \(records.count) APPS")
        title.fontName = "Menlo-Bold"; title.fontSize = 10; title.fontColor = rgb(0xF8E6C5); title.horizontalAlignmentMode = .left
        title.position = CGPoint(x: 16, y: size.height - 22); title.zPosition = 100; room.addChild(title)
        let device = SKLabelNode(text: selectedDevice ?? "全部设备")
        device.fontName = "Menlo"; device.fontSize = 9; device.fontColor = rgb(0xE0BA87); device.horizontalAlignmentMode = .right
        device.position = CGPoint(x: size.width - 16, y: size.height - 22); device.zPosition = 100; room.addChild(device)
    }

    private func addRect(_ rect: CGRect, color: SKColor, z: CGFloat) {
        let node = SKShapeNode(rect: rect)
        node.fillColor = color; node.strokeColor = .clear; node.isAntialiased = false; node.zPosition = z; room.addChild(node)
    }

    private func polygon(_ points: [CGPoint], fill: SKColor, stroke: SKColor, width: CGFloat) -> SKShapeNode {
        let path = CGMutablePath(); path.move(to: points[0]); points.dropFirst().forEach { path.addLine(to: $0) }; path.closeSubpath()
        let node = SKShapeNode(path: path); node.fillColor = fill; node.strokeColor = stroke; node.lineWidth = width; node.isAntialiased = false; node.zPosition = 0; return node
    }

    private func interpolate(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    private func diamond(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath(); path.move(to: CGPoint(x: 0, y: height / 2)); path.addLine(to: CGPoint(x: width / 2, y: 0)); path.addLine(to: CGPoint(x: 0, y: -height / 2)); path.addLine(to: CGPoint(x: -width / 2, y: 0)); path.closeSubpath(); return path
    }

    private func rgb(_ value: UInt32) -> SKColor {
        SKColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
