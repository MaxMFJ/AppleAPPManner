import AppKit
import SpriteKit

/// Deterministic, asset-free 48×48 pixel characters for the office scene.
enum SeatedCharacterArt {
    static let canvasSize = CGSize(width: 48, height: 48)
    private static let cachedFrames: [[SKTexture]] = (0..<4).flatMap { variant in
        [false, true].map { facingRight in
            (0..<4).map { texture(variant: variant, phase: $0, facingRight: facingRight) }
        }
    }

    static func frames(variant: Int = 0, facingRight: Bool = true) -> [SKTexture] {
        cachedFrames[(((variant % 4) + 4) % 4) * 2 + (facingRight ? 1 : 0)]
    }

    private static func texture(variant: Int, phase: Int, facingRight: Bool) -> SKTexture {
        guard let context = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8, bytesPerRow: 48 * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return SKTexture()
        }
        context.setShouldAntialias(false)
        if !facingRight { context.translateBy(x: 48, y: 0); context.scaleBy(x: -1, y: 1) }
        let palettes: [(NSColor, NSColor, NSColor)] = [
            (.init(calibratedRed: 0.16, green: 0.30, blue: 0.48, alpha: 1), .init(calibratedRed: 0.10, green: 0.07, blue: 0.10, alpha: 1), .init(calibratedRed: 0.88, green: 0.58, blue: 0.40, alpha: 1)),
            (.init(calibratedRed: 0.52, green: 0.18, blue: 0.22, alpha: 1), .init(calibratedRed: 0.82, green: 0.47, blue: 0.18, alpha: 1), .init(calibratedRed: 0.63, green: 0.35, blue: 0.22, alpha: 1)),
            (.init(calibratedRed: 0.20, green: 0.42, blue: 0.28, alpha: 1), .init(calibratedRed: 0.10, green: 0.16, blue: 0.16, alpha: 1), .init(calibratedRed: 0.48, green: 0.28, blue: 0.17, alpha: 1)),
            (.init(calibratedRed: 0.48, green: 0.30, blue: 0.58, alpha: 1), .init(calibratedRed: 0.22, green: 0.12, blue: 0.28, alpha: 1), .init(calibratedRed: 0.94, green: 0.70, blue: 0.52, alpha: 1))]
        let (shirt, hair, skin) = palettes[((variant % palettes.count) + palettes.count) % palettes.count]
        let dark = NSColor(calibratedWhite: 0.08, alpha: 1), pants = NSColor(calibratedRed: 0.16, green: 0.18, blue: 0.25, alpha: 1), accent = NSColor(calibratedRed: 0.93, green: 0.78, blue: 0.38, alpha: 1)
        func r(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: NSColor) {
            context.setFillColor(c.cgColor)
            context.fill(CGRect(x: x, y: y, width: w, height: h))
        }
        r(28, 7, 4, 3, dark); r(20, 8, 13, 5, pants)
        r(18, 10, 9, 9, pants); r(25, 10, 8, 5, pants); r(20, 5, 6, 7, pants); r(27, 4, 8, 4, dark); r(14, 5, 7, 4, dark); r(20, 8, 5, 3, skin)
        r(14, 19, 16, 15, dark); r(16, 20, 13, 13, shirt); r(20, 30, 7, 4, skin); r(18, 32, 8, 3, skin); r(14, 34, 14, 4, hair); r(12, 36, 15, 6, hair); r(14, 39, 12, 4, skin); r(13, 37, 3, 7, skin); r(24, 38, 4, 3, skin); r(27, 37, 2, 2, dark); r(20, 39, 2, 2, dark); r(13, 42, 12, 3, hair)
        r(15, 43, 7, 1, accent); r(19, 27, 5, 2, accent)
        r(27, 25, 9, 5, shirt); r(31, 22, 7, 5, skin); let wristY = 20 + ((phase == 1 || phase == 3) ? 1 : 0); r(34, wristY, 7, 3, skin); r(39, wristY - 2, 4, 3, dark); r(29, 22, 6, 3, skin); r(33, 19, 7, 3, skin)
        r(4, 17, 12, 3, dark); r(5, 20, 2, 8, dark); r(6, 26, 2, 2, accent); r(37, 18, 2, 2, accent); r(41, 18, 2, 2, accent)
        guard let image = context.makeImage() else { return SKTexture() }
        let result = SKTexture(cgImage: image)
        result.filteringMode = .nearest; return result
    }
}
