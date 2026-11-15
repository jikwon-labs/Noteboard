import AppKit
import Combine
import NoteboardCore

/// 메뉴바 아이콘과 메뉴. 업데이트가 있으면 아이콘에 점을 찍는다.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private weak var app: AppDelegate?
    private var cancellable: AnyCancellable?
    private var availableVersion: String?

    init(app: AppDelegate) {
        self.app = app
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        item.button?.setAccessibilityLabel("noteboard")
        refreshIcon()
        cancellable = app.updater.$availableVersion.receive(on: RunLoop.main).sink { [weak self] version in
            self?.availableVersion = version
            self?.refreshIcon()
        }
    }

    private func refreshIcon() {
        item.button?.image = Self.icon(badge: availableVersion != nil)
        item.button?.toolTip = availableVersion.map { "noteboard · 새 버전 \($0)" } ?? "noteboard"
    }

    /// 메모지 모양 아이콘. 점이 없으면 템플릿 이미지(메뉴바 색을 따른다).
    static func icon(badge: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let stroke = badge ? NSColor.labelColor : NSColor.black
            stroke.setStroke()
            let body = NSBezierPath(roundedRect: NSRect(x: 3.65, y: 1.65, width: 10.7, height: 13.7), xRadius: 2.4, yRadius: 2.4)
            body.lineWidth = 1.3
            body.stroke()
            for (y, w) in [(6.0, 6.0), (8.8, 6.0), (11.6, 3.6)] {
                let line = NSBezierPath()
                line.move(to: NSPoint(x: 6, y: y))
                line.line(to: NSPoint(x: 6 + w, y: y))
                line.lineWidth = 1.3
                line.lineCapStyle = .round
                line.stroke()
            }
            if badge {
                Theme.accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: 12, y: 0.5, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = !badge
        return image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let app else { return }
        let shortcut = Preferences.shared.shortcut(.newNote)
        let newNote = NSMenuItem(title: "새 노트", action: #selector(AppDelegate.newNote(_:)), keyEquivalent: shortcut.key)
        newNote.keyEquivalentModifierMask = MainMenu.modifierFlags(shortcut)
        newNote.target = app
        menu.addItem(newNote)
        let list = NSMenuItem(title: "노트 목록 열기", action: #selector(AppDelegate.showNoteList(_:)), keyEquivalent: "")
        list.target = app
        menu.addItem(list)
        menu.addItem(.separator())

        if let version = availableVersion {
            let install = NSMenuItem(title: "새 버전 \(version) 설치…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
            install.target = app
            install.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 6, weight: .regular).applying(.init(paletteColors: [Theme.accent])))
            menu.addItem(install)
        }
        let check = NSMenuItem(title: "업데이트 확인…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        check.target = app
        check.isEnabled = app.updater.isAvailable
        menu.addItem(check)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "설정…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        settings.target = app
        menu.addItem(settings)
        let folder = NSMenuItem(title: "저장 폴더 열기", action: #selector(AppDelegate.openStorageFolder(_:)), keyEquivalent: "")
        folder.target = app
        menu.addItem(folder)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "noteboard 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }
}
