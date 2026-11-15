import Foundation

/// 마크다운 목록에서 Enter 를 쳤을 때 다음 줄에 붙일 기호.
public enum ListContinuation {
    public enum Action: Equatable, Sendable {
        /// 줄바꿈 뒤에 이 글을 넣는다(줄바꿈 포함).
        case insert(String)
        /// 내용 없는 항목에서 Enter: 기호를 지우고 목록을 끝낸다.
        case clearLine
    }

    /// 커서가 줄 끝에 있을 때 그 줄 전체를 받아 할 일을 정한다. 목록이 아니면 nil.
    public static func onNewline(currentLine line: String) -> Action? {
        let ns = line as NSString
        let full = NSRange(location: 0, length: ns.length)

        // 체크박스·글머리표: "  - [ ] 내용"
        if let m = bullet.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: m.range(at: 1))
            let marker = ns.substring(with: m.range(at: 2))
            let hasBox = m.range(at: 3).location != NSNotFound
            let content = ns.substring(with: m.range(at: 4))
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return .clearLine }
            return .insert("\n" + indent + marker + " " + (hasBox ? "[ ] " : ""))
        }
        // 번호 목록: "1. 내용" → "2. "
        if let m = ordered.firstMatch(in: line, range: full) {
            let indent = ns.substring(with: m.range(at: 1))
            let number = Int(ns.substring(with: m.range(at: 2))) ?? 0
            let delimiter = ns.substring(with: m.range(at: 3))
            let content = ns.substring(with: m.range(at: 4))
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return .clearLine }
            return .insert("\n" + indent + "\(number + 1)" + delimiter + " ")
        }
        // 인용: "> 내용"
        if let m = quote.firstMatch(in: line, range: full) {
            let prefix = ns.substring(with: m.range(at: 1))
            let content = ns.substring(with: m.range(at: 2))
            if content.trimmingCharacters(in: .whitespaces).isEmpty { return .clearLine }
            return .insert("\n" + prefix.trimmingCharacters(in: .whitespaces) + " ")
        }
        return nil
    }

    /// 목록 줄인지(Tab 들여쓰기를 할지 정할 때 쓴다).
    public static func isListLine(_ line: String) -> Bool {
        let full = NSRange(location: 0, length: (line as NSString).length)
        return bullet.firstMatch(in: line, range: full) != nil || ordered.firstMatch(in: line, range: full) != nil
    }

    private static let bullet = try! NSRegularExpression(pattern: #"^(\s*)([-*+])\s+(\[[ xX]\]\s+)?(.*)$"#)
    private static let ordered = try! NSRegularExpression(pattern: #"^(\s*)(\d{1,9})([.)])\s+(.*)$"#)
    private static let quote = try! NSRegularExpression(pattern: #"^(\s*>\s?)(.*)$"#)
}
