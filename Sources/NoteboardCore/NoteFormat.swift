import Foundation

/// 노트 포맷. 파일 확장자가 곧 포맷이다.
public enum NoteFormat: String, CaseIterable, Codable, Sendable {
    case markdown
    case plainText

    public var fileExtension: String {
        switch self {
        case .markdown: return "md"
        case .plainText: return "txt"
        }
    }

    /// 제목 표시줄 버튼에 쓰는 짧은 이름.
    public var badge: String {
        switch self {
        case .markdown: return "MD"
        case .plainText: return "TXT"
        }
    }

    public var displayName: String {
        switch self {
        case .markdown: return "마크다운"
        case .plainText: return "텍스트"
        }
    }

    public var toggled: NoteFormat {
        self == .markdown ? .plainText : .markdown
    }

    public init?(fileExtension ext: String) {
        switch ext.lowercased() {
        case "md", "markdown": self = .markdown
        case "txt", "text": self = .plainText
        default: return nil
        }
    }
}
