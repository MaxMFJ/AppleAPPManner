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

    /// Geometry is authored around a shared desk origin. Keeping these anchors together
    /// prevents the chair, sitter and keyboard drifting independently during layout edits.
    private struct WorkstationAnchors {
        let desk: CGPoint
        let chair: CGPoint
        let sitter: CGPoint
        let monitor: CGPoint
        let keyboard: CGPoint

        init(center: CGPoint) {
            desk = CGPoint(x: center.x + 3, y: center.y - 5)
            chair = CGPoint(x: center.x - 15, y: center.y - 20)
            keyboard = CGPoint(x: center.x + 5, y: center.y - 10)
            monitor = CGPoint(x: center.x + 10, y: center.y + 20)
            // At 1.5x, the sitter's pelvis (14, 7) maps to the chair center and
            // typing hands (26, 15) land on the keyboard center.
            sitter = CGPoint(x: chair.x + (16 - 14) * 1.5, y: chair.y + (16 - 7) * 1.5)
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
        // Deep shadow under the cutaway office makes the floor read as a little diorama.
        let shadow = polygon([
            CGPoint(x: size.width * 0.5, y: 12), CGPoint(x: size.width - 16, y: size.height * 0.49),
            CGPoint(x: size.width * 0.5, y: size.height - 30), CGPoint(x: 16, y: size.height * 0.49)
        ], fill: rgb(0x17111B), stroke: rgb(0x332638), width: 5)
        room.addChild(shadow)

        // Two cutaway walls, with dark skirting, warm upper light and pixel-like wall panels.
        let backY = size.height * 0.66
        let leftWall = polygon([
            CGPoint(x: 18, y: size.height * 0.48), CGPoint(x: size.width * 0.5, y: backY + size.height * 0.28),
            CGPoint(x: size.width * 0.5, y: backY - 4), CGPoint(x: 18, y: size.height * 0.2)
        ], fill: rgb(0x242034), stroke: rgb(0x49324A), width: 2)
        let rightWall = polygon([
            CGPoint(x: size.width * 0.5, y: backY + size.height * 0.28), CGPoint(x: size.width - 18, y: size.height * 0.48),
            CGPoint(x: size.width - 18, y: size.height * 0.2), CGPoint(x: size.width * 0.5, y: backY - 4)
        ], fill: rgb(0x30283B), stroke: rgb(0x594052), width: 2)
        room.addChild(leftWall); room.addChild(rightWall)

        // Warm windows on the left wall.
        for i in 0..<3 {
            let t = CGFloat(i)
            let x = size.width * (0.10 + t * 0.115)
            let y = size.height * (0.46 + t * 0.065)
            addRect(CGRect(x: x, y: y, width: size.width * 0.065, height: size.height * 0.20), color: rgb(0xF5C66F), z: 3)
            addRect(CGRect(x: x + 4, y: y + 4, width: size.width * 0.065 - 8, height: size.height * 0.20 - 8), color: rgb(0xFFE5A0), z: 4)
            addRect(CGRect(x: x + 5, y: y + size.height * 0.09, width: size.width * 0.065 - 10, height: 3), color: rgb(0xD5924E), z: 5)
            addRect(CGRect(x: x + size.width * 0.032, y: y + 5, width: 3, height: size.height * 0.20 - 10), color: rgb(0xD5924E), z: 5)
        }
        // Bookshelves and a framed board on the far wall.
        drawBookshelf(at: CGPoint(x: size.width * 0.70, y: size.height * 0.78), width: size.width * 0.17, height: size.height * 0.23)
        drawBookshelf(at: CGPoint(x: size.width * 0.88, y: size.height * 0.66), width: size.width * 0.10, height: size.height * 0.20)
        drawNoticeBoard(at: CGPoint(x: size.width * 0.48, y: size.height * 0.83), width: size.width * 0.16, height: size.height * 0.11)
    }

    private func drawFloor() {
        let width = size.width * 0.86
        let height = size.height * 0.55
        let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
        let floor = polygon([
            CGPoint(x: center.x, y: center.y + height / 2), CGPoint(x: center.x + width / 2, y: center.y),
            CGPoint(x: center.x, y: center.y - height / 2), CGPoint(x: center.x - width / 2, y: center.y)
        ], fill: rgb(0xB87A43), stroke: rgb(0x4B2B25), width: 4)
        room.addChild(floor)

        let cols = 12, rows = 8
        let tileW = width / CGFloat(cols + rows) * 2
        let tileH = tileW * 0.5
        for row in 0..<rows {
            for col in 0..<cols {
                let x = center.x + (CGFloat(col - row) - CGFloat(cols - rows) / 2) * tileW / 2
                let y = center.y + (CGFloat(cols + rows - 2 - col - row) - CGFloat(cols + rows) / 2) * tileH / 2
                let path = diamond(width: tileW, height: tileH)
                let tile = SKShapeNode(path: path)
                tile.position = CGPoint(x: x, y: y)
                let colors: [UInt32] = [0xE8B86F, 0xDCA45F, 0xF0C77D, 0xCC9252]
                tile.fillColor = rgb(colors[(row + col) % colors.count])
                tile.strokeColor = rgb(0xA96E43)
                tile.lineWidth = 1
                tile.isAntialiased = false
                tile.zPosition = 1
                room.addChild(tile)
            }
        }
        // The exposed edge is a dark pixel-art cutaway trim.
        for i in 0..<18 {
            let t = CGFloat(i) / 18
            let x = 22 + (size.width - 44) * t
            let y = center.y - height * 0.47 + abs(t - 0.5) * height * 0.95
            let block = SKShapeNode(rectOf: CGSize(width: 8, height: 4))
            block.position = CGPoint(x: x, y: y)
            block.fillColor = rgb(i.isMultiple(of: 2) ? 0x54302A : 0x75412E)
            block.strokeColor = .clear
            block.zPosition = 2
            room.addChild(block)
        }
    }

    private func drawDecor() {
        // Soft pools from the left-side windows keep the room warm while remaining subtle.
        for index in 0..<3 {
            let t = CGFloat(index)
            let startX = size.width * (0.13 + t * 0.10)
            let startY = size.height * (0.47 + t * 0.045)
            let beam = polygon([
                CGPoint(x: startX, y: startY),
                CGPoint(x: startX + size.width * 0.045, y: startY - size.height * 0.015),
                CGPoint(x: startX + size.width * 0.20, y: startY - size.height * 0.19),
                CGPoint(x: startX + size.width * 0.15, y: startY - size.height * 0.17)
            ], fill: rgb(0xFFE19A).withAlphaComponent(0.07), stroke: .clear, width: 0)
            beam.zPosition = 2.4
            room.addChild(beam)
            beam.run(.repeatForever(.sequence([.fadeAlpha(to: 0.035, duration: 2.8), .fadeAlpha(to: 0.07, duration: 3.2)])))
        }
        addAsset(isoPlant, at: CGPoint(x: size.width * 0.12, y: size.height * 0.34), size: CGSize(width: 72, height: 82), z: 6)
        addAsset(isoPlant, at: CGPoint(x: size.width * 0.91, y: size.height * 0.35), size: CGSize(width: 72, height: 82), z: 6)
        // Break-room printer makes the shared office feel like a usable space, not a diagram.
        addAsset(isoPrinter, at: CGPoint(x: size.width * 0.29, y: size.height * 0.55), size: CGSize(width: 58, height: 58), z: 7)
    }

    private func drawWorkstations(animateArrivals: Bool) {
        guard !records.isEmpty else {
            let empty = SKLabelNode(text: "办公室空闲 · 等待 App 启动")
            empty.fontName = "Menlo-Bold"; empty.fontSize = 13; empty.fontColor = rgb(0x5F4838)
            empty.position = CGPoint(x: size.width / 2, y: size.height * 0.42); empty.zPosition = 40; room.addChild(empty)
            return
        }
        let cols = min(6, max(1, Int(ceil(sqrt(Double(records.count) * 1.55)))))
        let rows = Int(ceil(Double(records.count) / Double(cols)))
        // Give each process a legible workstation. The old tight grid stacked labels and
        // made the atlas furniture read as a row of tiny red blocks.
        let spacingX = min(176, size.width * 0.15)
        let spacingY = min(80, size.height * 0.145)
        let origin = CGPoint(x: size.width * 0.50, y: size.height * 0.405 + CGFloat(rows - 1) * spacingY * 0.5)

        for (index, app) in records.prefix(36).enumerated() {
            let row = index / cols, col = index % cols
            let x = origin.x + (CGFloat(col) - CGFloat(cols - 1) / 2) * spacingX + CGFloat(row % 2) * spacingX * 0.18
            let y = origin.y - CGFloat(row) * spacingY
            let shadow = SKShapeNode(ellipseOf: CGSize(width: 72, height: 18))
            shadow.position = CGPoint(x: x, y: y - 20); shadow.fillColor = rgb(0x6D422F).withAlphaComponent(0.22); shadow.strokeColor = .clear; shadow.zPosition = 8; room.addChild(shadow)

            let anchors = WorkstationAnchors(center: CGPoint(x: x, y: y))
            // Draw back-to-front: chair, desk shell, seated bust, then desktop items.
            // The 2D desk asset cannot be split into a separate front panel, so the
            // sprite is authored without exposed legs and overlaps only the desk edge.
            addAsset(isoChair, at: anchors.chair, size: CGSize(width: 58, height: 58), z: 10)
            drawDesk(at: anchors.desk, z: 12)
            drawCharacter(app, at: anchors.sitter, z: 13.5, animateArrival: animateArrivals && newArrivalKeys.contains(actorKey(app)))
            drawMonitor(at: anchors.monitor, active: app.isFrontmost)
            addAsset(isoKeyboard, at: anchors.keyboard, size: CGSize(width: 38, height: 38), z: 16)
            if index.isMultiple(of: 4) {
                let lampPoint = CGPoint(x: anchors.desk.x - 28, y: anchors.desk.y + 22)
                addGlow(at: CGPoint(x: lampPoint.x, y: lampPoint.y - 7), size: CGSize(width: 82, height: 42), color: rgb(0xF8C96C), alpha: 0.32, z: 12)
                addAsset(isoLamp, at: lampPoint, size: CGSize(width: 44, height: 44), z: 17)
            }
            drawAppLabel(app, at: CGPoint(x: x, y: y + 59), z: 30)
        }
        if records.count > 36 {
            let more = SKLabelNode(text: "+\(records.count - 36) 更多 App")
            more.fontName = "Menlo-Bold"; more.fontSize = 10; more.fontColor = rgb(0x6B4A38)
            more.position = CGPoint(x: size.width - 82, y: 20); more.zPosition = 40; room.addChild(more)
        }
    }

    private func drawCharacter(_ app: ProcessRecord, at point: CGPoint, z: CGFloat, animateArrival: Bool) {
        let key = actorKey(app)
        let characterIndex = stableIndex(for: key, count: characterSheets.count)
        let workFrames = seatedFrames(characterIndex: characterIndex)
        let workFrame = workFrames[0]
        let actor = SKSpriteNode(texture: workFrame, size: CGSize(width: 48, height: 48))
        actor.position = point
        actor.zPosition = z
        actor.texture?.filteringMode = .nearest
        actor.name = "pixel-character-\(key)"
        room.addChild(actor)
        characterNodes[key] = actor

        if animateArrival {
            // A compact sit-down motion ends in the real seated typing loop.
            actor.position = CGPoint(x: point.x, y: point.y + 12)
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

    /// Four crisp 32px seated pixel frames. Pose stays anchored at the pelvis; only
    /// forearms/hands move, so the character never appears to bob onto the tabletop.
    private func seatedFrames(characterIndex: Int) -> [SKTexture] {
        let shirts: [UInt32] = [0x42A56A, 0x8B65B4, 0xC66A3D, 0x4F83B8, 0xD0A23D, 0x58A6A0]
        let hairs: [UInt32] = [0x493027, 0x332A2E, 0x73412B, 0x3C302A, 0x56372D, 0x2C2B33]
        let shirt = rgb(shirts[characterIndex % shirts.count])
        let hair = rgb(hairs[characterIndex % hairs.count])
        return (0..<4).map { seatedFrame(shirt: shirt, hair: hair, typingPhase: $0) }
    }

    private func seatedFrame(shirt: SKColor, hair: SKColor, typingPhase: Int) -> SKTexture {
        let side = 32
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }
        context.setShouldAntialias(false)
        let outline = SKColor(red: 0.16, green: 0.13, blue: 0.16, alpha: 1)
        let skin = SKColor(red: 0.86, green: 0.60, blue: 0.40, alpha: 1)
        let pants = SKColor(red: 0.25, green: 0.30, blue: 0.40, alpha: 1)
        func block(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: SKColor) {
            context.setFillColor(color.cgColor)
            context.fill(CGRect(x: x, y: y, width: w, height: h))
        }
        // Crop the sitter at the desk: chair supports the hidden pelvis, with no
        // standing legs that could read as feet placed on the tabletop.
        block(8, 7, 13, 4, outline); block(9, 8, 11, 2, pants)
        block(8, 9, 14, 12, outline); block(9, 10, 12, 10, shirt)
        block(9, 17, 12, 2, rgb(0xE8B46E))
        // Head turned toward the monitor at screen-right, with a small visible profile.
        block(10, 19, 12, 11, outline); block(11, 20, 10, 9, skin)
        block(10, 25, 12, 5, hair); block(11, 23, 10, 3, hair)
        block(20, 22, 2, 2, skin) // nose/profile
        block(18, 24, 1, 1, outline) // eye
        // Upper arms angle forward. The wrists reach toward the keyboard anchor.
        block(7, 14, 5, 6, outline); block(8, 15, 4, 4, shirt)
        block(18, 14, 6, 6, outline); block(19, 15, 4, 4, shirt)
        block(11, 14, 4, 4, outline); block(12, 15, 3, 3, skin)
        block(22, 13 + (typingPhase.isMultiple(of: 2) ? 1 : 0), 6, 4, outline)
        block(23, 14 + (typingPhase.isMultiple(of: 2) ? 1 : 0), 4, 2, skin)
        block(16, 14 + (typingPhase.isMultiple(of: 2) ? 1 : 0), 5, 3, outline)
        block(17, 15 + (typingPhase.isMultiple(of: 2) ? 1 : 0), 4, 1, skin)
        guard let image = context.makeImage() else { return SKTexture() }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .nearest
        texture.usesMipmaps = false
        return texture
    }

    private func drawMonitor(at point: CGPoint, active: Bool) {
        addGlow(at: CGPoint(x: point.x, y: point.y + 4), size: CGSize(width: 76, height: 42), color: rgb(active ? 0x72BFEA : 0xA9C5D0), alpha: active ? 0.38 : 0.10, z: 14)
        addAsset(isoMonitor, at: point, size: CGSize(width: 54, height: 54), z: 17)
        let status = SKShapeNode(ellipseOf: CGSize(width: 4, height: 4))
        status.position = CGPoint(x: point.x + 15, y: point.y + 8)
        status.fillColor = rgb(active ? 0xA8E28B : 0x627B74)
        status.strokeColor = .clear
        status.zPosition = 18
        room.addChild(status)
    }

    private func drawDesk(at point: CGPoint, z: CGFloat) {
        addAsset(isoDesk, at: point, size: CGSize(width: 96, height: 96), z: z)
    }

    private func deskFace(_ points: [CGPoint], fill: SKColor, z: CGFloat) -> SKShapeNode {
        let face = polygon(points, fill: fill, stroke: rgb(0x673B2A), width: 2)
        face.zPosition = z
        return face
    }

    private func drawAppLabel(_ app: ProcessRecord, at point: CGPoint, z: CGFloat) {
        let label = SKLabelNode(text: String(app.name.prefix(14)))
        label.fontName = "Menlo-Bold"; label.fontSize = 9; label.fontColor = rgb(0x342A2D)
        label.position = point; label.verticalAlignmentMode = .center; label.zPosition = z + 1
        let width = min(120, max(48, CGFloat(app.name.count) * 5.5 + 16))
        let card = SKShapeNode(rectOf: CGSize(width: width, height: 18), cornerRadius: 4)
        card.position = point; card.fillColor = rgb(app.isFrontmost ? 0xFFF1C9 : 0xF4DDAF).withAlphaComponent(0.96)
        card.strokeColor = rgb(app.isFrontmost ? 0xC98847 : 0xB8885A); card.lineWidth = 1; card.zPosition = z; room.addChild(card); room.addChild(label)
        let department = SKShapeNode(rectOf: CGSize(width: 5, height: 11), cornerRadius: 1)
        department.position = CGPoint(x: point.x - width / 2 + 3, y: point.y); department.fillColor = rgb(app.department.colorHex); department.strokeColor = .clear; department.zPosition = z + 2; room.addChild(department)
        if app.isFrontmost {
            let bubble = SKLabelNode(text: "前台")
            bubble.fontName = "Menlo-Bold"; bubble.fontSize = 7; bubble.fontColor = rgb(0x855324); bubble.position = CGPoint(x: point.x, y: point.y + 14); bubble.zPosition = z + 2; room.addChild(bubble)
        }
    }

    private func drawBookshelf(at point: CGPoint, width: CGFloat, height: CGFloat) {
        addAsset(isoBookshelf, at: CGPoint(x: point.x + width / 2, y: point.y + height / 2), size: CGSize(width: width, height: height), z: 7)
    }

    private func addAsset(_ texture: SKTexture, at point: CGPoint, size: CGSize, z: CGFloat) {
        let sprite = SKSpriteNode(texture: texture, size: size)
        sprite.position = point
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

    private func diamond(width: CGFloat, height: CGFloat) -> CGPath {
        let path = CGMutablePath(); path.move(to: CGPoint(x: 0, y: height / 2)); path.addLine(to: CGPoint(x: width / 2, y: 0)); path.addLine(to: CGPoint(x: 0, y: -height / 2)); path.addLine(to: CGPoint(x: -width / 2, y: 0)); path.closeSubpath(); return path
    }

    private func rgb(_ value: UInt32) -> SKColor {
        SKColor(red: CGFloat((value >> 16) & 255) / 255, green: CGFloat((value >> 8) & 255) / 255, blue: CGFloat(value & 255) / 255, alpha: 1)
    }
}
