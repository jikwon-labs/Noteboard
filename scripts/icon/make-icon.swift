// 앱 아이콘을 그린다. 사용: swift scripts/icon/make-icon.swift <출력.iconset 폴더>
// 어두운 판 위에 메모 줄 셋. 첫 줄 앞의 목록 점만 강조색이다(symboard 와 같은 판·색 체계).
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ivory: UInt32 = 0xEFEBE4
let dim: UInt32 = 0x6E6E74
let accent: UInt32 = 0xE2A658

func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    let g = ctx.cgContext
    // 1024 격자, 위가 y=0.
    g.scaleBy(x: s / 1024, y: s / 1024)
    g.translateBy(x: 0, y: 1024)
    g.scaleBy(x: 1, y: -1)
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let path = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)
    g.saveGState()
    g.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.4))
    g.addPath(path); g.setFillColor(color(0x1B1B1D)); g.fillPath()
    g.restoreGState()
    g.addPath(path); g.setStrokeColor(color(0xFFFFFF, 0.08)); g.setLineWidth(3); g.strokePath()

    // 줄 번호 자리의 짧은 눈금(흐리게).
    g.setStrokeColor(color(dim)); g.setLineWidth(28); g.setLineCap(.round)
    for y in [372.0, 512.0, 652.0] {
        g.move(to: CGPoint(x: 250, y: y)); g.addLine(to: CGPoint(x: 268, y: y))
    }
    g.strokePath()

    // 메모 줄 셋.
    g.setStrokeColor(color(ivory)); g.setLineWidth(40); g.setLineCap(.round)
    g.move(to: CGPoint(x: 430, y: 372)); g.addLine(to: CGPoint(x: 740, y: 372))
    g.move(to: CGPoint(x: 360, y: 512)); g.addLine(to: CGPoint(x: 740, y: 512))
    g.move(to: CGPoint(x: 360, y: 652)); g.addLine(to: CGPoint(x: 600, y: 652))
    g.strokePath()

    // 첫 줄 앞 목록 점.
    g.setFillColor(color(accent)); g.fillEllipse(in: CGRect(x: 360 - 34, y: 372 - 34, width: 68, height: 68))
    return rep.representation(using: .png, properties: [:])!
}

let out = CommandLine.arguments.dropFirst().first ?? "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        try! draw(size: base * scale).write(to: URL(fileURLWithPath: "\(out)/\(name)"))
    }
}
print("wrote \(out)")
