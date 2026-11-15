import AppKit

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

/// 디자인 시안(noteboard 디자인 캔버스)의 색과 글꼴.
enum Theme {
    static let background = NSColor(hex: 0x1B1B1D)
    static let sidebarBackground = NSColor(hex: 0x151517)
    static let text = NSColor(hex: 0xE6E6E8)
    static let strongText = NSColor(hex: 0xF5F5F7)
    static let secondaryText = NSColor(hex: 0x8E8E93)
    static let syntax = NSColor(hex: 0x85858B)
    static let lineNumber = NSColor(hex: 0x85858B)
    static let currentLineNumber = NSColor(hex: 0xC7C7CC)
    static let currentLine = NSColor(white: 1, alpha: 0.035)
    static let accent = NSColor(hex: 0xE2A658)
    static let link = NSColor(hex: 0x8AB4F8)
    static let code = NSColor(hex: 0xE3C9A3)
    static let codeBackground = NSColor(white: 1, alpha: 0.08)
    static let rowSelection = NSColor(white: 1, alpha: 0.09)
    static let separator = NSColor(white: 1, alpha: 0.07)
    static let buttonIdle = NSColor(hex: 0xA1A1A6)

    static let accentHex = "#E2A658"

    static func editorFont(_ size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
}
