import AppKit
import NoteboardCore

/// 메뉴바 앱이라 메뉴 막대는 보이지 않지만, ⌘C·⌘V·⌘Z·⌘W 같은 단축키는 이 메뉴를 거쳐 동작한다.
enum MainMenu {
    private static let tagFor: [ShortcutAction: Int] = [.toggleSidebar: 101, .togglePreview: 102, .toggleFloating: 103]

    static func modifierFlags(_ s: Shortcut) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if s.command { flags.insert(.command) }
        if s.option { flags.insert(.option) }
        if s.control { flags.insert(.control) }
        if s.shift { flags.insert(.shift) }
        return flags
    }

    static func build() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu(title: "noteboard")
        appMenu.addItem(withTitle: "noteboard 정보", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(withTitle: "업데이트 확인…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "설정…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "noteboard 가리기", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "noteboard 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        add(appMenu, to: main)

        let file = NSMenu(title: "파일")
        file.addItem(withTitle: "새 노트", action: #selector(AppDelegate.newNote(_:)), keyEquivalent: "n")
        file.addItem(withTitle: "노트 목록 열기", action: #selector(AppDelegate.showNoteList(_:)), keyEquivalent: "")
        file.addItem(.separator())
        file.addItem(withTitle: "닫기", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        add(file, to: main)

        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "실행 복귀", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "오려두기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사하기", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let pastePlain = edit.addItem(withTitle: "서식 없이 붙여넣기", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let find = NSMenu(title: "찾기")
        find.addItem(findItem("찾기…", key: "f", tag: NSTextFinder.Action.showFindInterface.rawValue))
        let replace = findItem("찾아 바꾸기…", key: "f", tag: NSTextFinder.Action.showReplaceInterface.rawValue)
        replace.keyEquivalentModifierMask = [.command, .option]
        find.addItem(replace)
        find.addItem(findItem("다음 찾기", key: "g", tag: NSTextFinder.Action.nextMatch.rawValue))
        let previous = findItem("이전 찾기", key: "g", tag: NSTextFinder.Action.previousMatch.rawValue)
        previous.keyEquivalentModifierMask = [.command, .shift]
        find.addItem(previous)
        find.addItem(findItem("선택 항목으로 찾기", key: "e", tag: NSTextFinder.Action.setSearchString.rawValue))
        let findParent = edit.addItem(withTitle: "찾기", action: nil, keyEquivalent: "")
        edit.setSubmenu(find, for: findParent)
        add(edit, to: main)

        let view = NSMenu(title: "보기")
        view.addItem(withTitle: "사이드바", action: #selector(NoteWindowController.toggleSidebar(_:)), keyEquivalent: "").tag = tagFor[.toggleSidebar]!
        let search = view.addItem(withTitle: "노트 검색", action: #selector(NoteWindowController.showNoteSearch(_:)), keyEquivalent: "f")
        search.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(withTitle: "미리보기", action: #selector(NoteWindowController.toggleNotePreview(_:)), keyEquivalent: "").tag = tagFor[.togglePreview]!
        let format = view.addItem(withTitle: "일반 텍스트로 바꾸기", action: #selector(NoteWindowController.toggleNoteFormat(_:)), keyEquivalent: "m")
        format.keyEquivalentModifierMask = [.command, .shift]
        view.addItem(withTitle: "항상 위에", action: #selector(NoteWindowController.toggleFloating(_:)), keyEquivalent: "").tag = tagFor[.toggleFloating]!
        view.addItem(.separator())
        view.addItem(withTitle: "글자 크게", action: #selector(AppDelegate.increaseFontSize(_:)), keyEquivalent: "+")
        let bigger = view.addItem(withTitle: "글자 크게", action: #selector(AppDelegate.increaseFontSize(_:)), keyEquivalent: "=")
        bigger.isAlternate = false
        bigger.isHidden = true
        bigger.allowsKeyEquivalentWhenHidden = true
        view.addItem(withTitle: "글자 작게", action: #selector(AppDelegate.decreaseFontSize(_:)), keyEquivalent: "-")
        view.addItem(withTitle: "기본 글자 크기", action: #selector(AppDelegate.resetFontSize(_:)), keyEquivalent: "0")
        add(view, to: main)

        let window = NSMenu(title: "윈도우")
        window.addItem(withTitle: "최소화", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        add(window, to: main)

        applyShortcuts(to: main)
        return main
    }

    private static func findItem(_ title: String, key: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: key)
        item.tag = tag
        return item
    }

    private static func add(_ submenu: NSMenu, to main: NSMenu) {
        let item = NSMenuItem(title: submenu.title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        main.addItem(item)
    }

    /// 설정에서 바꾼 단축키를 메뉴에 반영한다.
    static func applyShortcuts(to main: NSMenu? = NSApp.mainMenu) {
        guard let main else { return }
        for (action, tag) in tagFor {
            for top in main.items {
                guard let item = top.submenu?.item(withTag: tag) else { continue }
                let s = Preferences.shared.shortcut(action)
                item.keyEquivalent = s.key
                item.keyEquivalentModifierMask = modifierFlags(s)
            }
        }
    }
}
