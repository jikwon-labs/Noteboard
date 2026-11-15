import Foundation

/// 사이드바 목록 한 줄과 검색에 필요한 노트 정보.
public struct NoteSummary: Identifiable, Equatable, Sendable {
    public var url: URL
    /// 사용자가 붙인 제목. 없으면 빈 문자열.
    public var title: String
    public var format: NoteFormat
    public var created: Date
    public var modified: Date
    public var firstLine: String
    public var body: String

    public var id: String { url.standardizedFileURL.path }

    public init(url: URL, title: String, format: NoteFormat, created: Date, modified: Date, body: String) {
        self.url = url
        self.title = title
        self.format = format
        self.created = created
        self.modified = modified
        self.body = body
        self.firstLine = NoteText.firstLine(of: body)
    }

    /// 목록 첫 줄: 제목이 있으면 제목, 없으면 첫 줄.
    public var displayTitle: String {
        if !title.isEmpty { return title }
        if !firstLine.isEmpty { return firstLine }
        return "빈 노트"
    }

    /// 목록 둘째 줄: 날짜, 제목이 있으면 첫 줄도 덧붙인다.
    public func subtitle(now: Date, calendar: Calendar = .current) -> String {
        let date = DateLabel.short(modified, now: now, calendar: calendar)
        if !title.isEmpty, !firstLine.isEmpty { return "\(date) · \(firstLine)" }
        return date
    }
}

public enum NoteSearch {
    /// 띄어쓰기로 나눈 낱말이 모두 제목·본문·날짜 표기 중 어딘가에 있으면 남긴다. 순서는 그대로.
    public static func filter(_ notes: [NoteSummary], query: String, now: Date, calendar: Calendar = .current) -> [NoteSummary] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(String.init)
        if terms.isEmpty { return notes }
        return notes.filter { note in
            let haystack = [
                note.title,
                note.body,
                DateLabel.searchText(note.modified, now: now, calendar: calendar),
                DateLabel.searchText(note.created, now: now, calendar: calendar),
            ].joined(separator: "\n")
            return terms.allSatisfy { haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
    }
}
