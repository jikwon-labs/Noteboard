import Foundation

/// 미리보기용 마크다운 → HTML. 노트에 자주 쓰는 문법만 다룬다:
/// 제목, 목록(중첩·번호·체크박스), 인용, 코드 블록, 가로줄, 굵게·기울임·취소선·코드·링크.
/// 문단 안의 줄바꿈은 그대로 줄바꿈으로 보여 준다(메모라서).
public enum MarkdownHTML {
    public static func render(_ text: String) -> String {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return renderBlocks(lines[...])
    }

    private struct ListItem {
        var indent: Int
        var ordered: Bool
        var start: Int
        var content: String
        var task: Bool?
    }

    private static func renderBlocks(_ lines: ArraySlice<String>) -> String {
        var html = ""
        var i = lines.startIndex
        var paragraph: [String] = []

        func flushParagraph() {
            if paragraph.isEmpty { return }
            html += "<p>" + paragraph.map(inline).joined(separator: "<br>\n") + "</p>\n"
            paragraph.removeAll()
        }

        while i < lines.endIndex {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let fenceMatch = match(fenceRegex, line) {
                flushParagraph()
                let marker = fenceMatch[1]
                let lang = fenceMatch[2].trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.endIndex, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(marker) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1 // 닫는 줄
                let cls = lang.isEmpty ? "" : " class=\"language-\(escape(lang))\""
                html += "<pre><code\(cls)>" + escape(body.joined(separator: "\n")) + "</code></pre>\n"
                continue
            }
            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }
            if let h = match(headingRegex, line) {
                flushParagraph()
                let level = h[1].count
                html += "<h\(level)>" + inline(h[2]) + "</h\(level)>\n"
                i += 1
                continue
            }
            if MarkdownHighlighter.hr.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) != nil {
                flushParagraph()
                html += "<hr>\n"
                i += 1
                continue
            }
            if match(quoteRegex, line) != nil {
                flushParagraph()
                var inner: [String] = []
                while i < lines.endIndex, let q = match(quoteRegex, lines[i]) {
                    inner.append(q[2])
                    i += 1
                }
                html += "<blockquote>\n" + renderBlocks(inner[...]) + "</blockquote>\n"
                continue
            }
            if listItem(line) != nil {
                flushParagraph()
                var items: [ListItem] = []
                while i < lines.endIndex, let item = listItem(lines[i]) {
                    items.append(item)
                    i += 1
                }
                html += renderList(items[...])
                continue
            }
            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return html
    }

    private static func listItem(_ line: String) -> ListItem? {
        if let m = match(bulletRegex, line) {
            var task: Bool?
            if !m[3].isEmpty { task = m[3].lowercased().contains("x") }
            return ListItem(indent: indentWidth(m[1]), ordered: false, start: 1, content: m[4], task: task)
        }
        if let m = match(orderedRegex, line) {
            return ListItem(indent: indentWidth(m[1]), ordered: true, start: Int(m[2]) ?? 1, content: m[3], task: nil)
        }
        return nil
    }

    private static func indentWidth(_ s: String) -> Int {
        s.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
    }

    private static func renderList(_ items: ArraySlice<ListItem>) -> String {
        guard let first = items.first else { return "" }
        let base = first.indent
        var html: String
        if first.ordered {
            html = first.start == 1 ? "<ol>\n" : "<ol start=\"\(first.start)\">\n"
        } else {
            html = "<ul>\n"
        }
        var idx = items.startIndex
        while idx < items.endIndex {
            let item = items[idx]
            // 같은 단계에서 글머리표 ↔ 번호가 바뀌면 목록을 새로 연다.
            if item.indent <= base, item.ordered != first.ordered { break }
            var j = idx + 1
            while j < items.endIndex, items[j].indent > base { j += 1 }
            if let done = item.task {
                html += "<li class=\"task\"><input type=\"checkbox\" disabled\(done ? " checked" : "")> "
                html += done ? "<span class=\"done\">" + inline(item.content) + "</span>" : inline(item.content)
            } else {
                html += "<li>" + inline(item.content)
            }
            if j > idx + 1 { html += "\n" + renderList(items[(idx + 1)..<j]) }
            html += "</li>\n"
            idx = j
        }
        html += first.ordered ? "</ol>\n" : "</ul>\n"
        if idx < items.endIndex { html += renderList(items[idx...]) }
        return html
    }

    // MARK: - 줄 안의 꾸밈

    public static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    static func inline(_ raw: String) -> String {
        var s = escape(raw)
        // 코드 조각은 안쪽을 꾸미지 않도록 자리 표시로 빼 둔다.
        var codes: [String] = []
        s = replace(codeRegex, in: s) { groups in
            codes.append(groups[2])
            return "\u{1}\(codes.count - 1)\u{1}"
        }
        s = replace(linkRegex, in: s) { g in
            "<a href=\"\(safeURL(g[2]))\">\(g[1])</a>"
        }
        s = replace(autolinkRegex, in: s) { g in "<a href=\"\(g[0])\">\(g[0])</a>" }
        s = replace(MarkdownHighlighter.bold, in: s) { g in "<strong>\(g[2])</strong>" }
        s = replace(MarkdownHighlighter.italicStar, in: s) { g in "<em>\(g[1])</em>" }
        s = replace(MarkdownHighlighter.italicUnderscore, in: s) { g in "<em>\(g[1])</em>" }
        s = replace(MarkdownHighlighter.strike, in: s) { g in "<del>\(g[1])</del>" }
        for (n, code) in codes.enumerated() {
            s = s.replacingOccurrences(of: "\u{1}\(n)\u{1}", with: "<code>\(code)</code>")
        }
        return s
    }

    private static func safeURL(_ url: String) -> String {
        let lower = url.lowercased().trimmingCharacters(in: .whitespaces)
        if lower.hasPrefix("javascript:") || lower.hasPrefix("data:") || lower.hasPrefix("vbscript:") { return "#" }
        return url
    }

    // MARK: - 정규식 도우미

    private static func match(_ regex: NSRegularExpression, _ s: String) -> [String]? {
        let ns = s as NSString
        guard let m = regex.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<m.numberOfRanges).map { idx in
            let r = m.range(at: idx)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    private static func replace(_ regex: NSRegularExpression, in s: String, _ make: ([String]) -> String) -> String {
        let ns = s as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let groups = (0..<m.numberOfRanges).map { idx -> String in
                let r = m.range(at: idx)
                return r.location == NSNotFound ? "" : ns.substring(with: r)
            }
            result += make(groups)
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }

    private static let fenceRegex = try! NSRegularExpression(pattern: #"^\s{0,3}(```|~~~)(.*)$"#)
    private static let headingRegex = try! NSRegularExpression(pattern: #"^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$"#)
    private static let quoteRegex = try! NSRegularExpression(pattern: #"^(\s*>\s?)(.*)$"#)
    private static let bulletRegex = try! NSRegularExpression(pattern: #"^(\s*)[-*+]\s+(\[([ xX])\]\s+)?(.*)$"#)
    private static let orderedRegex = try! NSRegularExpression(pattern: #"^(\s*)(\d{1,9})[.)]\s+(.*)$"#)
    private static let codeRegex = try! NSRegularExpression(pattern: #"(`+)(.+?)\1"#)
    private static let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\s]*)\)"#)
    private static let autolinkRegex = try! NSRegularExpression(pattern: #"(?<![\"=>])\bhttps?://[^\s<]+"#)
}
