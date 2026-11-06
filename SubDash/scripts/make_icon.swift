// 무채색 뉴모피즘 앱 아이콘을 그려 .iconset 폴더에 PNG 로 저장한다.
// 사용: swift scripts/make_icon.swift build/AppIcon.iconset
import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let s = CGFloat(px)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // 바탕 (양각 둥근 사각형)
    let inset = s * 0.1
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: body, cornerWidth: s * 0.2, cornerHeight: s * 0.2, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05,
                  color: NSColor(white: 0, alpha: 0.35).cgColor)
    ctx.addPath(path); ctx.setFillColor(NSColor(white: 0.88, alpha: 1).cgColor); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                       colors: [NSColor(white: 0.95, alpha: 1).cgColor, NSColor(white: 0.80, alpha: 1).cgColor] as CFArray,
                       locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])
    ctx.restoreGState()

    // 음각 원형 홈
    let c = CGPoint(x: s / 2, y: s / 2)
    let r = s * 0.26
    let ring = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
    ctx.saveGState()
    ctx.addEllipse(in: ring); ctx.clip()
    let g2 = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                        colors: [NSColor(white: 0.72, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor] as CFArray,
                        locations: [0, 1])!
    ctx.drawLinearGradient(g2, start: CGPoint(x: ring.minX, y: ring.maxY), end: CGPoint(x: ring.maxX, y: ring.minY), options: [])
    ctx.restoreGState()

    // 게이지 호 (진한 회색)
    ctx.setLineCap(.round)
    ctx.setLineWidth(s * 0.045)
    ctx.setStrokeColor(NSColor(white: 0.25, alpha: 1).cgColor)
    ctx.addArc(center: c, radius: r * 0.68, startAngle: .pi * 1.25, endAngle: .pi * 0.35, clockwise: true)
    ctx.strokePath()

    // 바늘 + 중심점 (양각)
    ctx.setLineWidth(s * 0.03)
    ctx.setStrokeColor(NSColor(white: 0.2, alpha: 1).cgColor)
    ctx.move(to: c)
    ctx.addLine(to: CGPoint(x: c.x + r * 0.45 * cos(.pi * 0.62), y: c.y + r * 0.45 * sin(.pi * 0.62)))
    ctx.strokePath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: s * 0.006, height: -s * 0.006), blur: s * 0.01,
                  color: NSColor(white: 0, alpha: 0.4).cgColor)
    let dot = s * 0.035
    ctx.setFillColor(NSColor(white: 0.9, alpha: 1).cgColor)
    ctx.fillEllipse(in: CGRect(x: c.x - dot, y: c.y - dot, width: dot * 2, height: dot * 2))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let d = render(base * scale) {
            try? d.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
        }
    }
}
print("icons written to \(outDir)")
