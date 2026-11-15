import AppKit
import NoteboardCore

/// 개발용: 실제 창과 NoteCenter 로 저장 흐름을 돌려 보고 결과를 출력한 뒤 끝낸다.
/// `NOTEBOARD_SELFTEST=1 Noteboard -storageFolder <빈 시험 폴더>` (scripts/selftest.sh)
enum SelfTest {
    static func run(app: AppDelegate) {
        app.setUpForSnapshots()
        let center = NoteCenter.shared
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) {
            print((ok ? "ok   " : "FAIL ") + what)
            if !ok { failures.append(what) }
        }
        let folder = center.library.folder
        func files() -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        }
        check(files().isEmpty, "시험 폴더가 비어 있다")

        // 1. 빈 창은 파일을 만들지 않고, 닫아도 아무것도 남지 않는다.
        let empty = center.newNote()
        empty.saveNow()
        check(files().isEmpty, "빈 창은 파일을 만들지 않는다")
        empty.window?.close()
        check(files().isEmpty, "빈 창을 닫아도 파일이 없다")

        // 2. 글을 쓰면 Untitled 파일이 생기고 내용이 저장된다.
        let a = center.newNote()
        a.editorTextView.insertText("# 첫 노트\n- 하나", replacementRange: NSRange(location: 0, length: 0))
        a.saveNow()
        let first = files()
        check(first.count == 1 && NoteNaming.isUntitledStem((first.first! as NSString).deletingPathExtension), "글을 쓰면 Untitled 파일 하나: \(first)")
        if let url = a.note.fileURL {
            check((try? center.library.read(url)) == "# 첫 노트\n- 하나", "내용이 그대로 저장된다")
        }
        check(a.window?.title == "첫 노트", "제목 표시줄은 첫 줄: \(a.window?.title ?? "")")

        // 3. 목록 이어 쓰기
        a.editorTextView.setSelectedRange(NSRange(location: (a.editorTextView.string as NSString).length, length: 0))
        a.editorTextView.insertNewline(nil)
        check(a.editorTextView.string.hasSuffix("- 하나\n- "), "Enter 를 치면 다음 줄에 '- ' 가 붙는다")
        a.editorTextView.insertNewline(nil)
        check(a.editorTextView.string.hasSuffix("- 하나\n"), "빈 항목에서 Enter 를 치면 기호가 지워진다")

        // 4. 제목 바꾸기 → 파일 이름이 바뀐다.
        if let url = a.note.fileURL {
            center.rename(url, to: "회의 메모")
            check(files() == ["회의 메모.md"], "제목을 바꾸면 파일 이름이 바뀐다: \(files())")
            check(a.window?.title == "회의 메모", "창 제목도 바뀐다")
        }

        // 5. 포맷 바꾸기 → 확장자가 바뀐다.
        a.toggleNoteFormat(nil)
        check(files() == ["회의 메모.txt"], "TXT 로 바꾸면 확장자가 바뀐다: \(files())")
        a.toggleNoteFormat(nil)
        check(files() == ["회의 메모.md"], "MD 로 되돌리면 확장자도 되돌아온다")

        // 6. 다른 편집기에서 고치면 창에 반영된다.
        if let url = a.note.fileURL {
            try? Data("밖에서 고친 내용".utf8).write(to: url)
            try? FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: url.path)
            a.checkExternalChange()
            check(a.editorTextView.string == "밖에서 고친 내용", "외부 수정이 창에 반영된다")
        }

        // 7. 사이드바: 빈 창에서 고르면 그 창에 열리고, 이미 열린 노트는 새 창을 만들지 않는다.
        center.reload()
        let b = center.newNote()
        let countBefore = center.controllers.count
        if let summary = center.summaries.first {
            center.open(summary, from: b)
            check(center.controllers.count == countBefore, "이미 열린 노트를 고르면 새 창을 만들지 않는다")
        }
        b.setSidebar(visible: true)
        let wide = b.window?.frame.width ?? 0
        b.setSidebar(visible: false)
        let narrow = b.window?.frame.width ?? 0
        check(abs((wide - narrow) - WindowGeometry.sidebarWidth) < 1, "사이드바를 열면 창이 220pt 넓어진다 (\(wide) → \(narrow))")

        // 7-1. 사이드바 검색: 실제 키 입력과 같은 경로(필드 편집기에 글자 넣기)로 걸러지는지.
        try? Data("장보기 목록\n우유, 계란".utf8).write(to: folder.appendingPathComponent("장보기.txt"))
        center.reload()
        b.setSidebar(visible: true)
        b.window?.makeFirstResponder(b.sidebarView.searchField)
        if let editor = b.sidebarView.searchField.currentEditor() as? NSTextView {
            editor.insertText("우유", replacementRange: editor.selectedRange())
        }
        check(b.sidebarView.visibleTitles == ["장보기"], "검색어를 치면 목록이 걸러진다: \(b.sidebarView.visibleTitles)")
        b.sidebarView.searchField.stringValue = ""
        b.sidebarView.searchField.sendAction(b.sidebarView.searchField.action, to: b.sidebarView.searchField.target)
        check(b.sidebarView.visibleTitles.count == 2, "검색어를 지우면 다시 다 보인다: \(b.sidebarView.visibleTitles)")
        b.setSidebar(visible: false)
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("장보기.txt"))
        center.reload()

        // 7-2. 메뉴 단축키: 설정의 단축키가 메뉴 항목에 붙어 있고, 그 항목이 창의 동작으로 이어지는지.
        // (시험 중에는 앱이 비활성이라 키 창이 없어서 키 이벤트 대신 메뉴 항목을 찾아 그 동작을 보낸다.)
        let menu = MainMenu.build()
        func menuItem(for shortcut: Shortcut) -> NSMenuItem? {
            var found: NSMenuItem?
            func walk(_ m: NSMenu) {
                for item in m.items {
                    if item.keyEquivalent == shortcut.key, item.keyEquivalentModifierMask == MainMenu.modifierFlags(shortcut) { found = item }
                    if let sub = item.submenu { walk(sub) }
                }
            }
            walk(menu)
            return found
        }
        for (action, expectVisible) in [(ShortcutAction.toggleSidebar, true), (.togglePreview, true), (.toggleFloating, !b.isFloating)] {
            let shortcut = Preferences.shared.shortcut(action)
            guard let item = menuItem(for: shortcut), let selector = item.action else {
                check(false, "\(shortcut.display) 메뉴 항목이 있다")
                continue
            }
            b.perform(selector, with: item)
            let state: Bool
            switch action {
            case .toggleSidebar: state = b.isSidebarVisible
            case .togglePreview: state = b.isPreviewing
            default: state = b.isFloating
            }
            check(state == expectVisible, "\(shortcut.display) → \(item.title)")
            b.perform(selector, with: item)
        }

        // 8. 쓰다가 전부 지우고 닫으면 파일이 지워진다.
        let c = center.newNote()
        c.editorTextView.insertText("잠깐 쓴 글", replacementRange: NSRange(location: 0, length: 0))
        c.saveNow()
        check(files().count == 2, "두 번째 노트 파일이 생긴다")
        c.editorTextView.selectAll(nil)
        c.editorTextView.insertText("", replacementRange: c.editorTextView.selectedRange())
        c.window?.close()
        check(files() == ["회의 메모.md"], "다 지우고 닫으면 파일이 지워진다: \(files())")

        // 9. 휴지통으로 보내면 창도 닫히고 파일이 사라진다.
        if let url = a.note.fileURL {
            center.trash(url)
            check(files().isEmpty, "휴지통으로 보내면 파일이 사라진다")
            check(!center.controllers.contains { $0 === a }, "그 노트의 창도 닫힌다")
        }

        print(failures.isEmpty ? "SELFTEST PASSED" : "SELFTEST FAILED (\(failures.count))")
        exit(failures.isEmpty ? 0 : 1)
    }
}
