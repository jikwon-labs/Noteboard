import Foundation

/// 사이드바 날짜 표시와 날짜 검색용 글.
public enum DateLabel {
    private static func formatter(_ format: String, _ calendar: Calendar) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ko_KR")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f
    }

    /// 오늘이면 `오늘 14:32`, 어제면 `어제`, 올해면 `11.14`, 그 전이면 `2025.11.14`.
    public static func short(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "오늘 " + formatter("HH:mm", calendar).string(from: date)
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "어제"
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return formatter("MM.dd", calendar).string(from: date)
        }
        return formatter("yyyy.MM.dd", calendar).string(from: date)
    }

    /// 검색에 걸리게 할 날짜 표기 여러 개를 한 줄로 이은 것.
    /// `11.14`, `11/14`, `2026-11-14`, `11월 14일`, `11월`, `오늘`·`어제` 등으로 찾을 수 있다.
    public static func searchText(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        var parts = [
            short(date, now: now, calendar: calendar),
            formatter("yyyy.MM.dd", calendar).string(from: date),
            formatter("yyyy-MM-dd", calendar).string(from: date),
            formatter("yyyy/MM/dd", calendar).string(from: date),
            formatter("M.d", calendar).string(from: date),
            formatter("M/d", calendar).string(from: date),
            formatter("MM/dd", calendar).string(from: date),
            formatter("M월 d일", calendar).string(from: date),
            formatter("yyyy년 M월 d일", calendar).string(from: date),
            formatter("EEEE", calendar).string(from: date),
        ]
        if calendar.isDate(date, inSameDayAs: now) { parts.append("오늘") }
        return parts.joined(separator: " ")
    }
}
