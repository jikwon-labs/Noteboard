import Foundation
import NoteboardCore

/// 창 하나가 들고 있는 노트. 파일은 내용이 처음 생길 때 만든다(빈 창은 파일이 없다).
final class NoteDocument {
    var fileURL: URL?
    /// 사용자가 붙인 제목. 없으면 빈 문자열.
    var title: String
    var format: NoteFormat
    var text: String
    let created: Date
    private(set) var savedText: String
    /// 마지막으로 읽거나 쓴 시점의 파일 수정 시각. 다른 편집기가 고쳤는지 판단할 때 쓴다.
    var knownModificationDate: Date?

    init(format: NoteFormat) {
        self.fileURL = nil
        self.title = ""
        self.format = format
        self.text = ""
        self.savedText = ""
        self.created = Date()
    }

    init(url: URL, title: String, format: NoteFormat, text: String, created: Date, modified: Date?) {
        self.fileURL = url
        self.title = title
        self.format = format
        self.text = text
        self.savedText = text
        self.created = created
        self.knownModificationDate = modified
    }

    var isBlank: Bool { NoteText.isBlank(text) }
    var isDirty: Bool { text != savedText }
    /// 파일도 내용도 없는 막 연 창. 사이드바에서 고른 노트를 이 창에 그대로 연다.
    var isPristine: Bool { fileURL == nil && text.isEmpty }

    var displayTitle: String {
        if !title.isEmpty { return title }
        let first = NoteText.firstLine(of: text)
        return first.isEmpty ? "새 노트" : first
    }

    func markSaved(modificationDate: Date?) {
        savedText = text
        knownModificationDate = modificationDate
    }

    func replaceFromDisk(_ newText: String, modificationDate: Date?) {
        text = newText
        savedText = newText
        knownModificationDate = modificationDate
    }
}
