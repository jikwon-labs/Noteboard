import Foundation

/// 키보드 단축키 하나. 전역 단축키(Carbon)는 keyCode 를, 메뉴 단축키는 key 글자를 쓴다.
public struct Shortcut: Codable, Equatable, Hashable, Sendable {
    public var keyCode: UInt16
    /// 수정 키 없이 눌렀을 때의 글자(소문자). 메뉴 keyEquivalent 로 쓴다.
    public var key: String
    public var command: Bool
    public var option: Bool
    public var control: Bool
    public var shift: Bool

    public init(keyCode: UInt16, key: String, command: Bool = false, option: Bool = false, control: Bool = false, shift: Bool = false) {
        self.keyCode = keyCode
        self.key = key.lowercased()
        self.command = command
        self.option = option
        self.control = control
        self.shift = shift
    }

    /// ⌘·⌥·⌃ 중 하나는 있어야 한다(Shift 만으로는 글자 입력과 겹친다).
    public var hasRequiredModifier: Bool { command || option || control }

    /// `⌃⌥⇧⌘N` 처럼 macOS 순서로 쓴 표기.
    public var display: String {
        var s = ""
        if control { s += "⌃" }
        if option { s += "⌥" }
        if shift { s += "⇧" }
        if command { s += "⌘" }
        return s + Self.keyName(keyCode: keyCode, key: key)
    }

    /// US 배열 기준 글자. 한글 입력 상태에서 눌러도 `n` 처럼 영문 글자를 얻으려고 keyCode 로 찾는다.
    public static func asciiKey(forKeyCode code: UInt16) -> String? {
        let table: [UInt16: String] = [
            0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v",
            11: "b", 12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 18: "1", 19: "2",
            20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
            29: "0", 30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p", 37: "l", 38: "j",
            39: "'", 40: "k", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "n", 46: "m", 47: ".",
            49: " ", 50: "`",
        ]
        return table[code]
    }

    public static func keyName(keyCode: UInt16, key: String) -> String {
        switch keyCode {
        case 36: return "↩"
        case 48: return "⇥"
        case 49: return "Space"
        case 51: return "⌫"
        case 53: return "⎋"
        case 117: return "⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        default: return key.uppercased()
        }
    }
}

/// 설정에서 바꿀 수 있는 단축키 목록.
public enum ShortcutAction: String, CaseIterable, Codable, Sendable {
    case newNote
    case toggleSidebar
    case togglePreview
    case toggleFloating

    public var title: String {
        switch self {
        case .newNote: return "새 노트 (어디서든)"
        case .toggleSidebar: return "사이드바 열기/닫기"
        case .togglePreview: return "MD 미리보기"
        case .toggleFloating: return "항상 위에 켜기/끄기"
        }
    }

    public var defaultShortcut: Shortcut {
        switch self {
        case .newNote: return Shortcut(keyCode: 45, key: "n", option: true, shift: true)
        case .toggleSidebar: return Shortcut(keyCode: 1, key: "s", command: true, control: true)
        case .togglePreview: return Shortcut(keyCode: 35, key: "p", command: true, shift: true)
        case .toggleFloating: return Shortcut(keyCode: 17, key: "t", command: true, shift: true)
        }
    }
}
