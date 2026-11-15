import Foundation

public enum NoteText {
    /// 사이드바에 보여 줄 첫 줄. 내용이 있는 첫 줄에서 마크다운 기호(`# `, `- `, `> `, `[ ] `, `1. `)를 뗀다.
    public static func firstLine(of text: String, maxLength: Int = 200) -> String {
        for raw in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("```") { continue }
            line = line.replacingOccurrences(
                of: #"^(#{1,6}\s+|>\s*|[-*+]\s+(\[[ xX]\]\s+)?|\d+[.)]\s+)"#,
                with: "", options: .regularExpression)
            line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.count > maxLength { line = String(line.prefix(maxLength)) }
            return line
        }
        return ""
    }

    public static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
