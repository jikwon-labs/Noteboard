import AppKit
import NoteboardCore

/// 노트 편집기. 현재 줄 강조, 빈 노트 안내 문구, 목록 이어 쓰기, Esc 로 창 닫기.
final class EditorTextView: NSTextView {
    var format: NoteFormat = .markdown
    var placeholder = "메모를 입력하세요"
    var placeholderFont: NSFont = Theme.editorFont(13)
    weak var lineNumberRuler: NSRulerView?

    /// 한글 조합 중에 누른 Esc 는 조합만 끝내고 창은 닫지 않는다.
    private var escapeWhileComposing = false

    override func keyDown(with event: NSEvent) {
        let composing = hasMarkedText()
        escapeWhileComposing = composing && event.keyCode == 53
        super.keyDown(with: event)
        escapeWhileComposing = false
    }

    override func cancelOperation(_ sender: Any?) {
        if escapeWhileComposing || hasMarkedText() {
            if hasMarkedText() { unmarkText() }
            return
        }
        window?.performClose(sender)
    }

    // MARK: 목록 이어 쓰기

    private func currentLineInfo() -> (lineStart: Int, contentsEnd: Int, text: String)? {
        let ns = string as NSString
        let sel = selectedRange()
        guard sel.length == 0, sel.location <= ns.length else { return nil }
        var start = 0
        var contentsEnd = 0
        ns.getLineStart(&start, end: nil, contentsEnd: &contentsEnd, for: NSRange(location: sel.location, length: 0))
        return (start, contentsEnd, ns.substring(with: NSRange(location: start, length: contentsEnd - start)))
    }

    override func insertNewline(_ sender: Any?) {
        guard format == .markdown, !hasMarkedText(), let info = currentLineInfo(),
              selectedRange().location == info.contentsEnd else {
            super.insertNewline(sender)
            return
        }
        switch ListContinuation.onNewline(currentLine: info.text) {
        case .insert(let continuation):
            insertText(continuation, replacementRange: selectedRange())
        case .clearLine:
            let range = NSRange(location: info.lineStart, length: info.contentsEnd - info.lineStart)
            if shouldChangeText(in: range, replacementString: "") {
                replaceCharacters(in: range, with: "")
                didChangeText()
            }
        case nil:
            super.insertNewline(sender)
        }
    }

    override func insertTab(_ sender: Any?) {
        guard format == .markdown, !hasMarkedText(), let info = currentLineInfo(),
              ListContinuation.isListLine(info.text) else {
            super.insertTab(sender)
            return
        }
        let at = NSRange(location: info.lineStart, length: 0)
        let caret = selectedRange().location
        if shouldChangeText(in: at, replacementString: "  ") {
            replaceCharacters(in: at, with: "  ")
            didChangeText()
            setSelectedRange(NSRange(location: caret + 2, length: 0))
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard format == .markdown, let info = currentLineInfo() else {
            super.insertBacktab(sender)
            return
        }
        let leading = info.text.prefix { $0 == " " }.count
        let remove = min(2, leading)
        guard remove > 0 else { return }
        let range = NSRange(location: info.lineStart, length: remove)
        let caret = selectedRange().location
        if shouldChangeText(in: range, replacementString: "") {
            replaceCharacters(in: range, with: "")
            didChangeText()
            setSelectedRange(NSRange(location: max(info.lineStart, caret - remove), length: 0))
        }
    }

    // MARK: 그리기

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        needsDisplay = true
        lineNumberRuler?.needsDisplay = true
    }

    /// 커서가 있는 줄(자동 줄바꿈된 부분 포함) 사각형.
    func currentLineRect() -> NSRect? {
        guard let lm = layoutManager, let tc = textContainer else { return nil }
        let ns = string as NSString
        let caret = min(selectedRange().location, ns.length)
        let origin = textContainerOrigin
        if ns.length == 0 || (caret == ns.length && (ns.length == 0 || ns.character(at: ns.length - 1) == 10)) {
            let extra = lm.extraLineFragmentRect
            if extra.isEmpty { return nil }
            return NSRect(x: 0, y: extra.minY + origin.y, width: bounds.width, height: extra.height)
        }
        let paragraph = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        let glyphs = lm.glyphRange(forCharacterRange: paragraph, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
        rect.origin.x = 0
        rect.size.width = bounds.width
        rect.origin.y += origin.y
        return rect
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        if selectedRange().length == 0, let line = currentLineRect(), line.intersects(rect) {
            Theme.currentLine.setFill()
            line.fill()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !hasMarkedText() else { return }
        let origin = textContainerOrigin
        let padding = textContainer?.lineFragmentPadding ?? 0
        let attrs: [NSAttributedString.Key: Any] = [.font: placeholderFont, .foregroundColor: Theme.syntax]
        (placeholder as NSString).draw(at: NSPoint(x: origin.x + padding + 3, y: origin.y), withAttributes: attrs)
    }

    // 커서를 2pt 로 조금 두껍게.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        var r = rect
        r.size.width = 2
        super.drawInsertionPoint(in: r, color: color, turnedOn: flag)
    }

    override func setNeedsDisplay(_ rect: NSRect, avoidAdditionalLayout flag: Bool) {
        var r = rect
        r.size.width += 1
        super.setNeedsDisplay(r, avoidAdditionalLayout: flag)
    }
}
