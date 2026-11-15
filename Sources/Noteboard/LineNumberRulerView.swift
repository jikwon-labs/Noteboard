import AppKit

/// 왼쪽 줄 번호. 자동 줄바꿈된 긴 줄도 번호는 하나로 센다. 커서가 있는 줄 번호는 밝게.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: EditorTextView?
    var textFont: NSFont = Theme.editorFont(13) {
        didSet { numberFont = .monospacedDigitSystemFont(ofSize: max(9, textFont.pointSize - 1.5), weight: .regular); invalidateLines() }
    }
    private var numberFont: NSFont = .monospacedDigitSystemFont(ofSize: 11.5, weight: .regular)
    private var lineStarts: [Int] = [0]
    private var cacheValid = false

    init(textView: EditorTextView, scrollView: NSScrollView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 34
    }

    required init(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var requiredThickness: CGFloat { ruleThickness }

    func invalidateLines() {
        cacheValid = false
        rebuildIfNeeded()
        let digits = max(2, String(lineStarts.count).count)
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: numberFont]).width
        let thickness = ceil(CGFloat(digits) * digitWidth + 20)
        if abs(thickness - ruleThickness) > 0.5 { ruleThickness = thickness }
        needsDisplay = true
    }

    private func rebuildIfNeeded() {
        guard !cacheValid, let tv = textView else { return }
        var starts = [0]
        var index = 0
        for unit in tv.string.utf16 {
            index += 1
            if unit == 10 { starts.append(index) }
        }
        lineStarts = starts
        cacheValid = true
    }

    private func lineIndex(for char: Int) -> Int {
        var lo = 0
        var hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= char { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    // 기본 구현이 그리는 경계선(제목 표시줄까지 비친다)을 빼고 번호만 그린다.
    override func draw(_ dirtyRect: NSRect) {
        drawHashMarksAndLabels(in: dirtyRect)
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        Theme.background.setFill()
        bounds.fill()
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer,
              let clip = scrollView?.contentView else { return }
        rebuildIfNeeded()

        let length = (tv.string as NSString).length
        let visible = clip.bounds
        let yOffset = convert(NSPoint.zero, from: tv).y
        let containerY = tv.textContainerOrigin.y
        let caretLine = lineIndex(for: min(tv.selectedRange().location, length))
        let glyphs = lm.glyphRange(forBoundingRect: visible, in: tc)
        let chars = lm.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let ascender = numberFont.ascender

        var line = lineIndex(for: chars.location)
        while line < lineStarts.count {
            let start = lineStarts[line]
            if start > NSMaxRange(chars) && start < length { break }
            var baseline: CGFloat
            if start >= length {
                // 마지막 빈 줄(줄바꿈 뒤)이나 아예 빈 노트.
                let extra = lm.extraLineFragmentRect
                if extra.isEmpty && length > 0 { break }
                baseline = extra.minY + tv.textFont.ascender
            } else {
                let glyph = lm.glyphIndexForCharacter(at: start)
                let fragment = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil, withoutAdditionalLayout: true)
                let isEmptyLine = (tv.string as NSString).character(at: start) == 10
                // 빈 줄은 줄바꿈 글리프 위치가 엉뚱하게 나와서 글꼴 기준으로 잡는다.
                baseline = fragment.minY + (isEmptyLine ? tv.textFont.ascender : lm.location(forGlyphAt: glyph).y)
            }
            let y = baseline + containerY + yOffset - ascender
            if y > bounds.maxY { break }
            let label = "\(line + 1)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: numberFont,
                .foregroundColor: line == caretLine ? Theme.currentLineNumber : Theme.lineNumber,
            ]
            let width = label.size(withAttributes: attrs).width
            label.draw(at: NSPoint(x: ruleThickness - 10 - width, y: y), withAttributes: attrs)
            line += 1
            if start >= length { break }
        }
    }
}

private extension NSTextView {
    var textFont: NSFont { font ?? Theme.editorFont(13) }
}
