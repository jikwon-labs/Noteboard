import AppKit
import NoteboardCore

/// 개발용: 창을 화면 밖에 띄워 PNG 로 저장하고 끝낸다. 디자인 시안과 맞춰 볼 때 쓴다.
/// `NOTEBOARD_SNAPSHOT_DIR=<폴더> Noteboard -storageFolder <시험 폴더>` (scripts/snapshots.sh)
enum Snapshots {
    static func run(outputDirectory: URL, app: AppDelegate) {
        try? FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        app.setUpForSnapshots()
        seedLibrary()
        NoteCenter.shared.reload()

        var shots: [(String, NSWindow)] = []

        let empty = NoteCenter.shared.newNote()
        shots.append(("1-new-note", empty.window!))

        let writing = NoteCenter.shared.newNote()
        writing.editorTextView.string = ""
        writing.editorTextView.insertText(sampleMarkdown, replacementRange: NSRange(location: 0, length: 0))
        shots.append(("2-writing", writing.window!))

        let plain = NoteCenter.shared.newNote()
        plain.toggleNoteFormat(nil)
        plain.editorTextView.insertText(samplePlain, replacementRange: NSRange(location: 0, length: 0))
        plain.setFloating(false)
        shots.append(("4-plain-text", plain.window!))

        let withSidebar = NoteCenter.shared.newNote()
        if let api = NoteCenter.shared.summaries.first(where: { $0.title == "API 메모" }) {
            NoteCenter.shared.open(api, from: withSidebar)
        }
        withSidebar.setSidebar(visible: true)
        shots.append(("5-sidebar", withSidebar.window!))

        let preview = NoteCenter.shared.newNote()
        preview.editorTextView.insertText(sampleMarkdown, replacementRange: NSRange(location: 0, length: 0))
        preview.toggleNotePreview(nil)
        shots.append(("3-preview", preview.window!))

        let settings = SettingsWindowController(app: app)
        shots.append(("7-settings", settings.window!))

        for (_, window) in shots {
            window.setFrameOrigin(NSPoint(x: -6000, y: 200))
            window.orderFrontRegardless()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            for (name, window) in shots {
                guard let view = window.contentView?.superview else { continue }
                view.layoutSubtreeIfNeeded()
                guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: outputDirectory.appendingPathComponent("\(name).png"))
                }
                print("snapshot \(name) \(Int(window.frame.width))x\(Int(window.frame.height))")
            }
            // 시험 노트가 저장되지 않게 닫지 않고 바로 끝낸다.
            exit(0)
        }
    }

    private static func seedLibrary() {
        let library = NoteLibrary(folder: Preferences.shared.storageFolder)
        try? library.ensureFolder()
        guard library.list().isEmpty else { return }
        let now = Date()
        let notes: [(String, String, NoteFormat, TimeInterval)] = [
            ("릴리즈 체크리스트", "# 릴리즈 체크리스트\n\n- Sparkle 서명 키 만들기\n- 릴리즈 레포 이름 정하기", .markdown, -60 * 30),
            ("", "배포 주기는 2주로, 급한 수정은 패치로\n\n- 다음 회의: 목요일 오후", .markdown, -60 * 60 * 3),
            ("API 메모", "# API 메모\n\nPOST /notes 응답 형식 정리\n- id, title, updatedAt\n- 실패하면 code, message", .markdown, -60 * 60 * 26),
            ("", "점심 먹고 할 일: 영수증 정리, 택배 반품", .plainText, -60 * 60 * 50),
            ("읽을 책", "# 읽을 책\n\n- 디자인과 인간 심리\n- 리팩터링 2판", .markdown, -60 * 60 * 24 * 7),
        ]
        for (title, body, format, offset) in notes {
            let date = now.addingTimeInterval(offset)
            if let url = try? library.create(text: body, title: title, format: format, created: date) {
                try? FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
            }
        }
    }

    private static let sampleMarkdown = """
    # 릴리즈 체크리스트

    - Sparkle 서명 키 만들기
    - **릴리즈 레포** 이름 정하기
    - [x] 앱 이름 정하기

    배포 전에 `appcast.xml` 위치 확인
    참고: [Sparkle 문서](https://sparkle-project.org/documentation/)
    """

    private static let samplePlain = """
    # 이건 TXT라 꾸밈 없이 그대로 보임
    배포 주기는 2주로. 급한 수정은 그때그때 패치 버전으로 올리고, 릴리즈 노트는 한 줄씩만 쓰기로 함

    - 다음 회의: 목요일 오후
    """
}
