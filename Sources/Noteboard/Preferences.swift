import Foundation
import Combine
import NoteboardCore

extension Notification.Name {
    /// 글자 크기·기본 포맷 등 창에 바로 반영할 설정이 바뀌었다.
    static let preferencesChanged = Notification.Name("noteboard.preferencesChanged")
    /// 단축키가 바뀌었다(전역 단축키 재등록, 메뉴 갱신).
    static let shortcutsChanged = Notification.Name("noteboard.shortcutsChanged")
    /// 저장 폴더의 노트 목록이 바뀌었다.
    static let notesChanged = Notification.Name("noteboard.notesChanged")
}

/// UserDefaults 에 저장하는 설정. 실행 인자 `-storageFolder /경로` 로 저장 폴더를 덮어쓸 수 있다(시험용).
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let storageFolder = "storageFolder"
        static let defaultFormat = "defaultFormat"
        static let fontSize = "fontSize"
        static let newWindowsFloat = "newWindowsFloat"
        static let shortcuts = "shortcuts"
        static let windowWidth = "windowWidth"
        static let windowHeight = "windowHeight"
    }

    static let defaultFontSize: Double = 13
    static let fontSizeRange: ClosedRange<Double> = 10...24

    static var defaultFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("noteboard")
    }

    private let defaults = UserDefaults.standard

    @Published var storageFolder: URL {
        didSet { defaults.set(storageFolder.path, forKey: Key.storageFolder) }
    }

    @Published var defaultFormat: NoteFormat {
        didSet { defaults.set(defaultFormat.rawValue, forKey: Key.defaultFormat) }
    }

    @Published var fontSize: Double {
        didSet {
            let clamped = min(max(fontSize, Self.fontSizeRange.lowerBound), Self.fontSizeRange.upperBound)
            if clamped != fontSize { fontSize = clamped; return }
            defaults.set(fontSize, forKey: Key.fontSize)
            NotificationCenter.default.post(name: .preferencesChanged, object: nil)
        }
    }

    @Published var newWindowsFloat: Bool {
        didSet { defaults.set(newWindowsFloat, forKey: Key.newWindowsFloat) }
    }

    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]

    private init() {
        if let path = defaults.string(forKey: Key.storageFolder), !path.isEmpty {
            storageFolder = URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
        } else {
            storageFolder = Self.defaultFolder
        }
        defaultFormat = NoteFormat(rawValue: defaults.string(forKey: Key.defaultFormat) ?? "") ?? .markdown
        let size = defaults.double(forKey: Key.fontSize)
        fontSize = size == 0 ? Self.defaultFontSize : size
        newWindowsFloat = defaults.object(forKey: Key.newWindowsFloat) as? Bool ?? true
        var loaded: [ShortcutAction: Shortcut] = [:]
        if let data = defaults.data(forKey: Key.shortcuts),
           let stored = try? JSONDecoder().decode([String: Shortcut].self, from: data) {
            for (k, v) in stored { if let action = ShortcutAction(rawValue: k) { loaded[action] = v } }
        }
        shortcuts = loaded
    }

    func shortcut(_ action: ShortcutAction) -> Shortcut {
        shortcuts[action] ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: Shortcut?, for action: ShortcutAction) {
        shortcuts[action] = shortcut
        let stored = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Key.shortcuts) }
        NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
    }

    /// 사용자가 마지막으로 조절한 창 크기(사이드바 폭 제외). 없으면 화면의 1/4.
    var savedWindowSize: CGSize? {
        get {
            let w = defaults.double(forKey: Key.windowWidth)
            let h = defaults.double(forKey: Key.windowHeight)
            return w > 0 && h > 0 ? CGSize(width: w, height: h) : nil
        }
        set {
            defaults.set(newValue?.width ?? 0, forKey: Key.windowWidth)
            defaults.set(newValue?.height ?? 0, forKey: Key.windowHeight)
        }
    }
}
