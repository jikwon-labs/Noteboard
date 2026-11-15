import Foundation

/// 파일 이름 규칙. 파일 이름(확장자 뺀 부분)이 곧 제목이다.
/// 제목이 없는 노트는 `Untitled-yyyyMMdd-HHmmss` 로 저장하고, 화면에는 첫 줄을 대신 보여 준다.
public enum NoteNaming {
    public static let untitledPrefix = "Untitled-"
    public static let maxTitleLength = 120

    private static func stampFormatter(_ timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }

    public static func untitledStem(for date: Date, timeZone: TimeZone = .current) -> String {
        untitledPrefix + stampFormatter(timeZone).string(from: date)
    }

    /// `Untitled-20261116-143205` 또는 겹쳐서 붙은 `Untitled-20261116-143205 (2)`.
    public static func isUntitledStem(_ stem: String) -> Bool {
        stem.range(of: #"^Untitled-\d{8}-\d{6}( \(\d+\))?$"#, options: .regularExpression) != nil
    }

    /// 파일 이름 → 화면 제목. 제목 없는 노트는 빈 문자열.
    public static func title(fromStem stem: String) -> String {
        isUntitledStem(stem) ? "" : stem
    }

    /// 사용자가 입력한 제목을 파일 이름으로 쓸 수 있게 다듬는다. 남는 게 없으면 빈 문자열(= 제목 없음).
    public static func sanitizedTitle(_ title: String) -> String {
        var s = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        s = String(s.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(Character.init))
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        // 점으로 시작하면 숨김 파일이 된다.
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        if s.count > maxTitleLength {
            s = String(s.prefix(maxTitleLength)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    /// 폴더에 이미 있는 이름과 겹치지 않는 `이름.확장자`. 겹치면 `이름 (2).확장자` 처럼 번호를 붙인다.
    /// macOS 기본 디스크는 대소문자를 가리지 않으므로 비교도 대소문자를 무시한다.
    public static func uniqueFileName(stem: String, ext: String, existing: Set<String>) -> String {
        let taken = Set(existing.map { $0.lowercased() })
        let first = "\(stem).\(ext)"
        if !taken.contains(first.lowercased()) { return first }
        var n = 2
        while true {
            let candidate = "\(stem) (\(n)).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }
}
