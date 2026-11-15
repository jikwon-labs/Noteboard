import AppKit
import NoteboardCore

/// 입력하면서 바로 마크다운 꾸밈을 입힌다. 일반 텍스트 모드에서는 기본 글꼴만.
/// 한글 조합 중에는 건드리지 않고, 조합이 끝나면 다시 칠한다.
final class MarkdownStyler: NSObject, NSTextStorageDelegate {
    weak var textView: NSTextView?
    var format: NoteFormat = .markdown
    var fontSize: CGFloat = 13
    private var isStyling = false

    var baseFont: NSFont { Theme.editorFont(fontSize) }

    var baseAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = (fontSize * 0.35).rounded()
        return [.font: baseFont, .foregroundColor: Theme.text, .paragraphStyle: paragraph]
    }

    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters), !isStyling else { return }
        if let tv = textView, tv.hasMarkedText() { return }
        style(textStorage)
    }

    /// 전체를 다시 칠한다(포맷·글자 크기를 바꿨을 때).
    func restyle(_ storage: NSTextStorage) {
        storage.beginEditing()
        style(storage)
        storage.endEditing()
    }

    private func style(_ storage: NSTextStorage) {
        isStyling = true
        defer { isStyling = false }
        let full = NSRange(location: 0, length: storage.length)
        let base = baseAttributes
        storage.setAttributes(base, range: full)
        // 편집 처리 중에 typingAttributes 를 바꾸면 글이 비었을 때 AppKit 이 예외를 던진다. 처리가 끝난 뒤에 바꾼다.
        DispatchQueue.main.async { [weak textView] in
            guard let tv = textView, !tv.hasMarkedText() else { return }
            tv.typingAttributes = base
        }
        if format == .markdown, full.length > 0 {
            for token in MarkdownHighlighter.tokens(in: storage.string) {
                guard NSMaxRange(token.range) <= storage.length, token.range.length > 0 else { continue }
                storage.addAttributes(attributes(for: token.style), range: token.range)
            }
        }
        // SF Mono 에 없는 한글 등은 대체 글꼴로 바꿔 줘야 보인다. 글꼴을 새로 칠했으니 다시 맞춘다.
        storage.fixAttributes(in: full)
    }

    private func attributes(for style: MarkdownStyle) -> [NSAttributedString.Key: Any] {
        switch style {
        case .syntax:
            return [.foregroundColor: Theme.syntax]
        case .heading(let level):
            let bump: CGFloat = level == 1 ? 1 : (level == 2 ? 0.5 : 0)
            return [.font: Theme.editorFont(fontSize + bump, weight: .bold), .foregroundColor: Theme.strongText]
        case .bold:
            return [.font: Theme.editorFont(fontSize, weight: .bold), .foregroundColor: Theme.strongText]
        case .italic:
            return [.font: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)]
        case .strikethrough:
            return [.strikethroughStyle: NSUnderlineStyle.single.rawValue]
        case .inlineCode:
            return [.foregroundColor: Theme.code, .backgroundColor: Theme.codeBackground]
        case .codeBlock:
            return [.foregroundColor: Theme.code]
        case .link:
            return [.foregroundColor: Theme.link]
        case .listMarker:
            return [.foregroundColor: Theme.accent]
        case .done:
            return [.foregroundColor: Theme.syntax, .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                    .strikethroughColor: Theme.syntax]
        case .quote:
            return [.foregroundColor: Theme.secondaryText]
        }
    }
}
