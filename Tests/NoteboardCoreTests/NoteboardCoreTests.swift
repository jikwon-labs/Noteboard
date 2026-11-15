import XCTest
@testable import NoteboardCore

final class NamingTests: XCTestCase {
    func testUntitledStemRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_794_700_000)
        let stem = NoteNaming.untitledStem(for: date, timeZone: TimeZone(identifier: "Asia/Seoul")!)
        XCTAssertTrue(stem.hasPrefix("Untitled-"))
        XCTAssertTrue(NoteNaming.isUntitledStem(stem))
        XCTAssertTrue(NoteNaming.isUntitledStem(stem + " (2)"))
        XCTAssertEqual(NoteNaming.title(fromStem: stem), "")
        XCTAssertEqual(NoteNaming.title(fromStem: "API 메모"), "API 메모")
        XCTAssertFalse(NoteNaming.isUntitledStem("Untitled"))
    }

    func testSanitizedTitle() {
        XCTAssertEqual(NoteNaming.sanitizedTitle("  회의 / 메모:정리  "), "회의 - 메모-정리")
        XCTAssertEqual(NoteNaming.sanitizedTitle("...숨김"), "숨김")
        XCTAssertEqual(NoteNaming.sanitizedTitle("줄\n바꿈\t탭"), "줄바꿈탭")
        XCTAssertEqual(NoteNaming.sanitizedTitle("   "), "")
        XCTAssertEqual(NoteNaming.sanitizedTitle(String(repeating: "가", count: 300)).count, NoteNaming.maxTitleLength)
    }

    func testUniqueFileName() {
        let existing: Set = ["메모.md", "메모 (2).md", "Other.txt"]
        XCTAssertEqual(NoteNaming.uniqueFileName(stem: "메모", ext: "md", existing: existing), "메모 (3).md")
        XCTAssertEqual(NoteNaming.uniqueFileName(stem: "메모", ext: "txt", existing: existing), "메모.txt")
        XCTAssertEqual(NoteNaming.uniqueFileName(stem: "other", ext: "txt", existing: existing), "other (2).txt")
    }
}

final class TextTests: XCTestCase {
    func testFirstLineStripsMarkdown() {
        XCTAssertEqual(NoteText.firstLine(of: "\n\n# 릴리즈 체크리스트\n- 하나"), "릴리즈 체크리스트")
        XCTAssertEqual(NoteText.firstLine(of: "- [x] 끝난 일"), "끝난 일")
        XCTAssertEqual(NoteText.firstLine(of: "  > 인용문"), "인용문")
        XCTAssertEqual(NoteText.firstLine(of: "3. 셋째"), "셋째")
        XCTAssertEqual(NoteText.firstLine(of: "```swift\nlet a = 1\n```"), "let a = 1")
        XCTAssertEqual(NoteText.firstLine(of: "   \n  "), "")
    }

    func testFormat() {
        XCTAssertEqual(NoteFormat(fileExtension: "MD"), .markdown)
        XCTAssertEqual(NoteFormat(fileExtension: "txt"), .plainText)
        XCTAssertNil(NoteFormat(fileExtension: "rtf"))
        XCTAssertEqual(NoteFormat.markdown.toggled, .plainText)
    }
}

final class DateAndSearchTests: XCTestCase {
    var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Seoul")!
        return c
    }()

    func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    func testShortLabels() {
        let now = date(2026, 11, 16, 15)
        XCTAssertEqual(DateLabel.short(date(2026, 11, 16, 14, 32), now: now, calendar: calendar), "오늘 14:32")
        XCTAssertEqual(DateLabel.short(date(2026, 11, 15, 9), now: now, calendar: calendar), "어제")
        XCTAssertEqual(DateLabel.short(date(2026, 11, 14), now: now, calendar: calendar), "11.14")
        XCTAssertEqual(DateLabel.short(date(2025, 3, 2), now: now, calendar: calendar), "2025.03.02")
    }

    func testSearchByTitleBodyAndDate() {
        let now = date(2026, 11, 16, 15)
        let notes = [
            NoteSummary(url: URL(fileURLWithPath: "/n/릴리즈 체크리스트.md"), title: "릴리즈 체크리스트", format: .markdown,
                        created: date(2026, 11, 16, 9), modified: date(2026, 11, 16, 14, 32), body: "# 릴리즈\n- Sparkle 키"),
            NoteSummary(url: URL(fileURLWithPath: "/n/Untitled-20261114-120000.md"), title: "", format: .markdown,
                        created: date(2026, 11, 14), modified: date(2026, 11, 14), body: "점심 먹고 할 일: 택배 반품"),
        ]
        XCTAssertEqual(NoteSearch.filter(notes, query: "", now: now, calendar: calendar).count, 2)
        XCTAssertEqual(NoteSearch.filter(notes, query: "릴리즈", now: now, calendar: calendar).map(\.title), ["릴리즈 체크리스트"])
        XCTAssertEqual(NoteSearch.filter(notes, query: "sparkle", now: now, calendar: calendar).count, 1)
        XCTAssertEqual(NoteSearch.filter(notes, query: "택배", now: now, calendar: calendar).first?.firstLine, "점심 먹고 할 일: 택배 반품")
        XCTAssertEqual(NoteSearch.filter(notes, query: "11.14", now: now, calendar: calendar).count, 1)
        XCTAssertEqual(NoteSearch.filter(notes, query: "11월 14일", now: now, calendar: calendar).count, 1)
        XCTAssertEqual(NoteSearch.filter(notes, query: "오늘", now: now, calendar: calendar).count, 1)
        XCTAssertEqual(NoteSearch.filter(notes, query: "11월 반품", now: now, calendar: calendar).count, 1)
        XCTAssertEqual(NoteSearch.filter(notes, query: "없는말", now: now, calendar: calendar).count, 0)
    }

    func testSummaryDisplay() {
        let now = date(2026, 11, 16, 15)
        let titled = NoteSummary(url: URL(fileURLWithPath: "/a.md"), title: "API 메모", format: .markdown,
                                 created: now, modified: date(2026, 11, 15), body: "# API 메모\nPOST /notes")
        XCTAssertEqual(titled.displayTitle, "API 메모")
        XCTAssertEqual(titled.subtitle(now: now, calendar: calendar), "어제 · API 메모")
        let untitled = NoteSummary(url: URL(fileURLWithPath: "/b.md"), title: "", format: .markdown,
                                   created: now, modified: date(2026, 11, 14), body: "\n배포 주기는 2주")
        XCTAssertEqual(untitled.displayTitle, "배포 주기는 2주")
        XCTAssertEqual(untitled.subtitle(now: now, calendar: calendar), "11.14")
    }
}

final class LibraryTests: XCTestCase {
    var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("noteboard-tests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    func testCreateWriteRenameList() throws {
        let lib = NoteLibrary(folder: folder)
        let created = Date(timeIntervalSince1970: 1_794_700_000)
        let url = try lib.create(text: "첫 줄\n둘째 줄", title: "", format: .markdown, created: created)
        XCTAssertTrue(NoteNaming.isUntitledStem(url.deletingPathExtension().lastPathComponent))
        XCTAssertEqual(url.pathExtension, "md")

        let before = try url.resourceValues(forKeys: [.creationDateKey]).creationDate
        try lib.write("바뀐 내용", to: url)
        XCTAssertEqual(try lib.read(url), "바뀐 내용")
        let after = try url.resourceValues(forKeys: [.creationDateKey]).creationDate
        XCTAssertEqual(before, after, "저장해도 생성 시각은 그대로여야 한다")

        let renamed = try lib.rename(url, title: "회의/메모", format: .plainText)
        XCTAssertEqual(renamed.lastPathComponent, "회의-메모.txt")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        let second = try lib.create(text: "x", title: "회의-메모", format: .plainText)
        XCTAssertEqual(second.lastPathComponent, "회의-메모 (2).txt")

        // 대소문자만 바뀌는 이름 변경
        let caseURL = try lib.create(text: "y", title: "abc", format: .markdown)
        let caseRenamed = try lib.rename(caseURL, title: "ABC", format: .markdown)
        XCTAssertEqual(caseRenamed.lastPathComponent, "ABC.md")

        // 제목을 지우면 다시 Untitled 이름
        let untitledAgain = try lib.rename(renamed, title: "  ", format: .plainText)
        XCTAssertTrue(NoteNaming.isUntitledStem(untitledAgain.deletingPathExtension().lastPathComponent))

        try Data("숨김".utf8).write(to: folder.appendingPathComponent(".hidden.md"))
        try Data("그림".utf8).write(to: folder.appendingPathComponent("image.png"))
        let list = lib.list()
        XCTAssertEqual(list.count, 3)
        XCTAssertTrue(list.allSatisfy { NoteLibrary.isNoteFile($0.url) })
    }

    func testDeleteIfBlankAndMoveAll() throws {
        let lib = NoteLibrary(folder: folder)
        let blank = try lib.create(text: "  \n ", title: "", format: .markdown)
        let kept = try lib.create(text: "내용", title: "남김", format: .markdown)
        try lib.deleteIfBlank(blank)
        try lib.deleteIfBlank(kept)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blank.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))

        let other = folder.appendingPathComponent("moved")
        try Data("이미 있음".utf8).write(to: { try! FileManager.default.createDirectory(at: other, withIntermediateDirectories: true); return other.appendingPathComponent("남김.md") }())
        let mapping = try lib.moveAll(to: other)
        XCTAssertEqual(mapping.count, 1)
        XCTAssertEqual(mapping[kept]?.lastPathComponent, "남김 (2).md")
    }
}

final class ListContinuationTests: XCTestCase {
    func testBullets() {
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "- 하나"), .insert("\n- "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "  * 둘"), .insert("\n  * "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "- [x] 끝"), .insert("\n- [ ] "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "- "), .clearLine)
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "- [ ] "), .clearLine)
    }

    func testOrderedAndQuote() {
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "9. 아홉"), .insert("\n10. "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "1) 첫"), .insert("\n2) "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "> 인용"), .insert("\n> "))
        XCTAssertEqual(ListContinuation.onNewline(currentLine: "> "), .clearLine)
        XCTAssertNil(ListContinuation.onNewline(currentLine: "그냥 문장"))
        XCTAssertNil(ListContinuation.onNewline(currentLine: "-하이픈"))
    }
}

final class GeometryTests: XCTestCase {
    func testDefaultSizeIsQuarterOfScreen() {
        let size = WindowGeometry.defaultSize(screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982))
        XCTAssertEqual(size, CGSize(width: 378, height: 245))
        let tiny = WindowGeometry.defaultSize(screenFrame: CGRect(x: 0, y: 0, width: 800, height: 400))
        XCTAssertEqual(tiny, WindowGeometry.minimumSize)
    }

    func testCascade() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let size = CGSize(width: 378, height: 245)
        let first = WindowGeometry.origin(for: size, in: visible, occupied: [])
        XCTAssertEqual(first, CGPoint(x: 567, y: 353))
        let second = WindowGeometry.origin(for: size, in: visible, occupied: [first])
        XCTAssertEqual(second, CGPoint(x: 589, y: 331))
    }

    func testSidebarExpandCollapse() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 950)
        let frame = CGRect(x: 500, y: 300, width: 378, height: 245)
        let wide = WindowGeometry.expandedForSidebar(frame, visibleFrame: visible)
        XCTAssertEqual(wide, CGRect(x: 280, y: 300, width: 598, height: 245))
        XCTAssertEqual(WindowGeometry.collapsedFromSidebar(wide), frame)
        let atEdge = WindowGeometry.expandedForSidebar(CGRect(x: 100, y: 0, width: 378, height: 245), visibleFrame: visible)
        XCTAssertEqual(atEdge.minX, 0)
        XCTAssertEqual(atEdge.width, 598)
    }
}

final class ShortcutTests: XCTestCase {
    func testDisplay() {
        XCTAssertEqual(ShortcutAction.newNote.defaultShortcut.display, "⌥⇧N")
        XCTAssertEqual(ShortcutAction.toggleSidebar.defaultShortcut.display, "⌃⌘S")
        XCTAssertEqual(Shortcut(keyCode: 49, key: " ", command: true).display, "⌘Space")
        XCTAssertFalse(Shortcut(keyCode: 45, key: "n", shift: true).hasRequiredModifier)
        let defaults = Set(ShortcutAction.allCases.map(\.defaultShortcut))
        XCTAssertEqual(defaults.count, ShortcutAction.allCases.count, "기본 단축키끼리 겹치면 안 된다")
    }
}

final class MarkdownTests: XCTestCase {
    func styles(_ text: String) -> [(MarkdownStyle, String)] {
        let ns = text as NSString
        return MarkdownHighlighter.tokens(in: text).map { ($0.style, ns.substring(with: $0.range)) }
    }

    func testHighlighterHeadingAndInline() {
        let t = styles("# 제목\n- **굵게** 와 `코드`\n- [x] 끝난 일")
        XCTAssertTrue(t.contains { $0.0 == .syntax && $0.1 == "# " })
        XCTAssertTrue(t.contains { $0.0 == .heading(1) && $0.1 == "제목" })
        XCTAssertTrue(t.contains { $0.0 == .listMarker && $0.1 == "-" })
        XCTAssertTrue(t.contains { $0.0 == .bold && $0.1 == "굵게" })
        XCTAssertTrue(t.contains { $0.0 == .inlineCode && $0.1 == "코드" })
        XCTAssertTrue(t.contains { $0.0 == .done && $0.1 == "끝난 일" })
        XCTAssertFalse(t.contains { $0.0 == .italic }, "**굵게** 를 기울임으로 잘못 읽으면 안 된다")
    }

    func testHighlighterCodeFenceAndSnakeCase() {
        let t = styles("```\n# 코드 안\n```\nsnake_case_name *기울임*")
        XCTAssertTrue(t.contains { $0.0 == .codeBlock && $0.1 == "# 코드 안" })
        XCTAssertFalse(t.contains { if case .heading = $0.0 { return true }; return false })
        XCTAssertEqual(t.filter { $0.0 == .italic }.map(\.1), ["기울임"])
    }

    func testHighlighterLinkAndUnicodeOffsets() {
        let text = "😀 [문서](https://example.com) 끝"
        let t = styles(text)
        XCTAssertTrue(t.contains { $0.0 == .link && $0.1 == "문서" })
        XCTAssertTrue(t.contains { $0.0 == .syntax && $0.1 == "](https://example.com)" })
    }

    func testHTML() {
        let html = MarkdownHTML.render("""
        # 제목
        - 하나
          - 안쪽
        - [x] 끝
        1. 첫

        문단 **굵게** <script>
        둘째 줄 [링크](https://a.com) `a<b`
        > 인용
        ```
        <코드>
        ```
        """)
        XCTAssertTrue(html.contains("<h1>제목</h1>"))
        XCTAssertTrue(html.contains("<li>하나\n<ul>\n<li>안쪽</li>"))
        XCTAssertTrue(html.contains("<input type=\"checkbox\" disabled checked>"))
        XCTAssertTrue(html.contains("<ol>\n<li>첫</li>"))
        XCTAssertTrue(html.contains("<strong>굵게</strong> &lt;script&gt;<br>"))
        XCTAssertTrue(html.contains("<a href=\"https://a.com\">링크</a>"))
        XCTAssertTrue(html.contains("<code>a&lt;b</code>"))
        XCTAssertTrue(html.contains("<blockquote>\n<p>인용</p>"))
        XCTAssertTrue(html.contains("<pre><code>&lt;코드&gt;</code></pre>"))
        XCTAssertFalse(html.contains("<script>"))
    }

    func testHTMLBlocksUnsafeLinks() {
        XCTAssertTrue(MarkdownHTML.render("[x](javascript:alert(1))").contains("href=\"#\""))
        XCTAssertTrue(MarkdownHTML.render("주소 https://example.com/a_b_c 끝").contains("<a href=\"https://example.com/a_b_c\">"))
    }
}
