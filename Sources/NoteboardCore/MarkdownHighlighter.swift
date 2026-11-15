import Foundation

/// 편집 중 마크다운 꾸밈. 기호(`#`, `**`, `` ` `` 등)는 흐리게 남기고 내용만 꾸민다.
public enum MarkdownStyle: Equatable, Sendable {
    /// 흐리게 보일 마크다운 기호.
    case syntax
    case heading(Int)
    case bold
    case italic
    case strikethrough
    case inlineCode
    case codeBlock
    case link
    /// 목록 기호(`-`, `1.`). 강조색.
    case listMarker
    /// 완료된 체크박스 항목의 내용. 흐리게 + 취소선.
    case done
    case quote
}

public struct MarkdownToken: Equatable, Sendable {
    public var style: MarkdownStyle
    /// NSString(UTF-16) 기준 범위.
    public var range: NSRange

    public init(_ style: MarkdownStyle, _ range: NSRange) {
        self.style = style
        self.range = range
    }
}

public enum MarkdownHighlighter {
    public static func tokens(in text: String) -> [MarkdownToken] {
        let ns = text as NSString
        var out: [MarkdownToken] = []
        var inFence = false
        var loc = 0
        while loc < ns.length {
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(nil, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: loc, length: 0))
            let lineRange = NSRange(location: loc, length: contentsEnd - loc)
            let line = ns.substring(with: lineRange)
            processLine(line, offset: loc, inFence: &inFence, into: &out)
            if lineEnd <= loc { break }
            loc = lineEnd
        }
        return out
    }

    private static func processLine(_ line: String, offset: Int, inFence: inout Bool, into out: inout [MarkdownToken]) {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)
        func shifted(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }

        if fence.firstMatch(in: line, range: full) != nil {
            out.append(MarkdownToken(.syntax, shifted(full)))
            inFence.toggle()
            return
        }
        if inFence {
            if full.length > 0 { out.append(MarkdownToken(.codeBlock, shifted(full))) }
            return
        }
        if let m = heading.firstMatch(in: line, range: full) {
            let level = m.range(at: 1).length
            let markerEnd = m.range(at: 2).location + m.range(at: 2).length
            out.append(MarkdownToken(.syntax, shifted(NSRange(location: 0, length: markerEnd))))
            let content = m.range(at: 3)
            if content.length > 0 {
                out.append(MarkdownToken(.heading(level), shifted(content)))
                inline(ns.substring(with: content), offset: offset + content.location, into: &out)
            }
            return
        }
        if hr.firstMatch(in: line, range: full) != nil {
            out.append(MarkdownToken(.syntax, shifted(full)))
            return
        }
        if let m = quote.firstMatch(in: line, range: full) {
            out.append(MarkdownToken(.syntax, shifted(m.range(at: 1))))
            let content = m.range(at: 2)
            if content.length > 0 {
                out.append(MarkdownToken(.quote, shifted(content)))
                inline(ns.substring(with: content), offset: offset + content.location, into: &out)
            }
            return
        }
        if let m = bullet.firstMatch(in: line, range: full) {
            out.append(MarkdownToken(.listMarker, shifted(m.range(at: 2))))
            let box = m.range(at: 4)
            let content = m.range(at: 5)
            if box.location != NSNotFound {
                out.append(MarkdownToken(.syntax, shifted(box)))
                let checked = ns.substring(with: box).lowercased().contains("x")
                if checked, content.length > 0 { out.append(MarkdownToken(.done, shifted(content))) }
            }
            if content.length > 0 { inline(ns.substring(with: content), offset: offset + content.location, into: &out) }
            return
        }
        if let m = ordered.firstMatch(in: line, range: full) {
            out.append(MarkdownToken(.listMarker, shifted(m.range(at: 2))))
            let content = m.range(at: 4)
            if content.length > 0 { inline(ns.substring(with: content), offset: offset + content.location, into: &out) }
            return
        }
        inline(line, offset: offset, into: &out)
    }

    private static func inline(_ text: String, offset: Int, into out: inout [MarkdownToken]) {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        if full.length == 0 { return }
        func shifted(_ r: NSRange) -> NSRange { NSRange(location: r.location + offset, length: r.length) }
        var protected: [NSRange] = []
        func isFree(_ r: NSRange) -> Bool { !protected.contains { NSIntersectionRange($0, r).length > 0 } }

        for m in code.matches(in: text, range: full) {
            let whole = m.range
            let ticks = m.range(at: 1).length
            out.append(MarkdownToken(.syntax, shifted(NSRange(location: whole.location, length: ticks))))
            out.append(MarkdownToken(.inlineCode, shifted(m.range(at: 2))))
            out.append(MarkdownToken(.syntax, shifted(NSRange(location: whole.location + whole.length - ticks, length: ticks))))
            protected.append(whole)
        }
        for m in link.matches(in: text, range: full) where isFree(m.range) {
            let textRange = m.range(at: 1)
            out.append(MarkdownToken(.syntax, shifted(NSRange(location: m.range.location, length: 1))))
            out.append(MarkdownToken(.link, shifted(textRange)))
            let tailStart = textRange.location + textRange.length
            out.append(MarkdownToken(.syntax, shifted(NSRange(location: tailStart, length: m.range.location + m.range.length - tailStart))))
        }
        func wrapped(_ regex: NSRegularExpression, markerLength: Int, style: MarkdownStyle) {
            for m in regex.matches(in: text, range: full) where isFree(m.range) {
                let whole = m.range
                out.append(MarkdownToken(.syntax, shifted(NSRange(location: whole.location, length: markerLength))))
                out.append(MarkdownToken(style, shifted(NSRange(location: whole.location + markerLength, length: whole.length - markerLength * 2))))
                out.append(MarkdownToken(.syntax, shifted(NSRange(location: whole.location + whole.length - markerLength, length: markerLength))))
            }
        }
        wrapped(bold, markerLength: 2, style: .bold)
        wrapped(italicStar, markerLength: 1, style: .italic)
        wrapped(italicUnderscore, markerLength: 1, style: .italic)
        wrapped(strike, markerLength: 2, style: .strikethrough)
    }

    static let fence = try! NSRegularExpression(pattern: #"^\s{0,3}(```|~~~)"#)
    static let heading = try! NSRegularExpression(pattern: #"^(#{1,6})(\s+)(.*)$"#)
    static let hr = try! NSRegularExpression(pattern: #"^\s{0,3}([-*_])(\s*\1){2,}\s*$"#)
    static let quote = try! NSRegularExpression(pattern: #"^(\s*>\s?)(.*)$"#)
    static let bullet = try! NSRegularExpression(pattern: #"^(\s*)([-*+])(\s+)(\[[ xX]\]\s+)?(.*)$"#)
    static let ordered = try! NSRegularExpression(pattern: #"^(\s*)(\d{1,9}[.)])(\s+)(.*)$"#)
    static let code = try! NSRegularExpression(pattern: #"(`+)(.+?)\1"#)
    static let link = try! NSRegularExpression(pattern: #"\[([^\]\n]+)\]\(([^)\s]*)\)"#)
    static let bold = try! NSRegularExpression(pattern: #"(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#)
    static let italicStar = try! NSRegularExpression(pattern: #"(?<![*\w])\*(?![\s*])(.+?)(?<![\s*])\*(?![*\w])"#)
    static let italicUnderscore = try! NSRegularExpression(pattern: #"(?<![_\w])_(?![\s_])(.+?)(?<![\s_])_(?![_\w])"#)
    static let strike = try! NSRegularExpression(pattern: #"~~(?=\S)(.+?)(?<=\S)~~"#)
}
