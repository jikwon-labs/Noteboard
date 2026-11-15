import AppKit
import NoteboardCore

/// Esc 로 닫히는 노트 창.
final class NoteWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(sender)
    }
}

/// 노트 창 하나: 제목 표시줄 버튼, 사이드바, 편집기(줄 번호), 미리보기.
final class NoteWindowController: NSWindowController, NSWindowDelegate, NSTextViewDelegate {
    private(set) var note: NoteDocument

    private let sidebar: SidebarView
    private let editorContainer = NSView()
    private let scrollView = NSScrollView()
    private let textView: EditorTextView
    private let ruler: LineNumberRulerView
    private let styler = MarkdownStyler()
    private var preview: PreviewView?

    private(set) var isSidebarVisible = false
    private(set) var isPreviewing = false
    private(set) var isFloating = false
    private var discarded = false
    private var saveWork: DispatchWorkItem?
    private var editorLeadingToRoot: NSLayoutConstraint!
    private var editorLeadingToSidebar: NSLayoutConstraint!
    private var observers: [NSObjectProtocol] = []

    private var sidebarButton: NSButton!
    private var formatButton: NSButton!
    private var previewButton: NSButton!
    private var pinButton: NSButton!

    init(note: NoteDocument) {
        self.note = note

        let window = NoteWindow(contentRect: NSRect(x: 0, y: 0, width: 378, height: 245),
                                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Theme.background
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = WindowGeometry.minimumSize
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        // TextKit 1 로 직접 쌓는다(줄 번호 계산이 줄 조각 단위라서).
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 4
        layoutManager.addTextContainer(container)
        textView = EditorTextView(frame: .zero, textContainer: container)

        scrollView.documentView = textView
        ruler = LineNumberRulerView(textView: textView, scrollView: scrollView)
        sidebar = SidebarView()

        super.init(window: window)
        window.delegate = self
        sidebar.controller = self

        buildEditor(storage: storage)
        buildLayout(in: window)
        buildTitlebar(in: window)

        setFloating(Preferences.shared.newWindowsFloat)
        applyFontSize()
        apply(note)

        observers.append(NotificationCenter.default.addObserver(forName: .preferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.applyFontSize()
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification,
                                                                object: scrollView.contentView, queue: .main) { [weak self] _ in
            self?.ruler.needsDisplay = true
        })
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - 화면 만들기

    private func buildEditor(storage: NSTextStorage) {
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.drawsBackground = true
        textView.backgroundColor = Theme.background
        textView.insertionPointColor = Theme.accent
        textView.textColor = Theme.text
        textView.selectedTextAttributes = [.backgroundColor: Theme.accent.withAlphaComponent(0.32)]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self
        textView.lineNumberRuler = ruler
        textView.setAccessibilityLabel("노트 내용")

        styler.textView = textView
        storage.delegate = styler

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = Theme.background
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        scrollView.automaticallyAdjustsContentInsets = false
    }

    private func buildLayout(in window: NSWindow) {
        guard let root = window.contentView else { return }
        let contentTop = (window.contentLayoutGuide as? NSLayoutGuide)?.topAnchor ?? root.topAnchor
        sidebar.isHidden = true
        for v in [sidebar, editorContainer] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(scrollView)

        editorLeadingToRoot = editorContainer.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        editorLeadingToSidebar = editorContainer.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor)
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: WindowGeometry.sidebarWidth),

            editorLeadingToRoot,
            editorContainer.topAnchor.constraint(equalTo: contentTop),
            editorContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            editorContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            scrollView.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
        ])
        sidebar.attachSearchTop(to: contentTop)
    }

    private func symbolButton(_ symbol: String, label: String, action: Selector) -> NSButton {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(config) ?? NSImage()
        let button = NSButton(image: image, target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.contentTintColor = Theme.buttonIdle
        button.toolTip = label
        button.setAccessibilityLabel(label)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 24),
            button.heightAnchor.constraint(equalToConstant: 22),
        ])
        return button
    }

    private func accessory(_ views: [NSView], attribute: NSLayoutConstraint.Attribute, width: CGFloat) -> NSTitlebarAccessoryViewController {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: attribute == .leading ? 2 : 0, bottom: 0, right: attribute == .trailing ? 6 : 0)
        stack.frame = NSRect(x: 0, y: 0, width: width, height: 28)
        let vc = NSTitlebarAccessoryViewController()
        vc.view = stack
        vc.layoutAttribute = attribute
        return vc
    }

    private func buildTitlebar(in window: NSWindow) {
        sidebarButton = symbolButton("sidebar.left", label: "사이드바", action: #selector(toggleSidebar(_:)))
        previewButton = symbolButton("eye", label: "미리보기", action: #selector(toggleNotePreview(_:)))
        pinButton = symbolButton("pin", label: "항상 위에", action: #selector(toggleFloating(_:)))

        formatButton = NSButton(title: "MD", target: self, action: #selector(toggleNoteFormat(_:)))
        formatButton.isBordered = false
        formatButton.wantsLayer = true
        formatButton.layer?.cornerRadius = 4
        formatButton.layer?.borderWidth = 1
        formatButton.layer?.borderColor = NSColor(white: 1, alpha: 0.16).cgColor
        formatButton.toolTip = "포맷 바꾸기 (마크다운 / 텍스트)"
        formatButton.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            formatButton.widthAnchor.constraint(equalToConstant: 32),
            formatButton.heightAnchor.constraint(equalToConstant: 18),
        ])

        window.addTitlebarAccessoryViewController(accessory([sidebarButton], attribute: .leading, width: 30))
        window.addTitlebarAccessoryViewController(accessory([formatButton, previewButton, pinButton], attribute: .trailing, width: 98))
    }

    // MARK: - 노트 내용

    private func apply(_ doc: NoteDocument) {
        textView.format = doc.format
        styler.format = doc.format
        textView.string = doc.text
        if let storage = textView.textStorage { styler.restyle(storage) }
        textView.setSelectedRange(NSRange(location: (doc.text as NSString).length, length: 0))
        textView.scrollToEndOfDocument(nil)
        if doc.fileURL != nil { textView.scrollToBeginningOfDocument(nil); textView.setSelectedRange(NSRange(location: 0, length: 0)) }
        ruler.invalidateLines()
        updateTitle()
        updateButtons()
    }

    /// 비어 있는 이 창에 사이드바에서 고른 노트를 연다.
    func load(_ doc: NoteDocument) {
        saveWork?.cancel()
        if isPreviewing { setPreview(false) }
        note = doc
        apply(doc)
        sidebar.highlightCurrent()
    }

    private func updateTitle() {
        window?.title = note.displayTitle
    }

    private func updateButtons() {
        formatButton.attributedTitle = NSAttributedString(string: note.format.badge, attributes: [
            .font: NSFont.systemFont(ofSize: 10.5, weight: .semibold),
            .foregroundColor: Theme.buttonIdle,
            .kern: 0.3,
        ])
        formatButton.setAccessibilityLabel("포맷: \(note.format.displayName)")
        previewButton.isEnabled = note.format == .markdown
        previewButton.alphaValue = note.format == .markdown ? 1 : 0.3
        tint(previewButton, on: isPreviewing)
        tint(pinButton, on: isFloating)
        tint(sidebarButton, on: isSidebarVisible, color: Theme.currentLineNumber)
        let pinSymbol = isFloating ? "pin.fill" : "pin"
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        pinButton.image = NSImage(systemSymbolName: pinSymbol, accessibilityDescription: "항상 위에")?.withSymbolConfiguration(config)
    }

    private func tint(_ button: NSButton, on: Bool, color: NSColor = Theme.accent) {
        button.contentTintColor = on ? color : Theme.buttonIdle
        button.wantsLayer = true
        button.layer?.cornerRadius = 5
        button.layer?.backgroundColor = on ? color.withAlphaComponent(0.13).cgColor : NSColor.clear.cgColor
    }

    private func applyFontSize() {
        let size = CGFloat(Preferences.shared.fontSize)
        styler.fontSize = size
        textView.font = Theme.editorFont(size)
        textView.placeholderFont = Theme.editorFont(size)
        ruler.textFont = Theme.editorFont(size)
        if let storage = textView.textStorage { styler.restyle(storage) }
        if isPreviewing { preview?.show(markdown: textView.string, fontSize: size) }
    }

    func textDidChange(_ notification: Notification) {
        note.text = textView.string
        ruler.invalidateLines()
        updateTitle()
        scheduleSave()
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.discarded else { return }
            NoteCenter.shared.save(self.note)
            self.updateTitle()
            self.sidebar.highlightCurrent()
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        guard !discarded else { return }
        if textView.hasMarkedText() { textView.unmarkText() }
        note.text = textView.string
        NoteCenter.shared.save(note)
    }

    /// 다른 편집기에서 파일을 고쳤으면(그리고 여기서 고친 게 없으면) 다시 읽는다.
    func checkExternalChange() {
        guard let url = note.fileURL, !note.isDirty, !textView.hasMarkedText(),
              FileManager.default.fileExists(atPath: url.path) else { return }
        let library = NoteLibrary(folder: url.deletingLastPathComponent())
        let modified = library.modificationDate(of: url)
        guard modified != note.knownModificationDate, let text = try? library.read(url) else { return }
        if text == note.text {
            note.knownModificationDate = modified
            return
        }
        let selection = textView.selectedRange()
        note.replaceFromDisk(text, modificationDate: modified)
        textView.string = text
        if let storage = textView.textStorage { styler.restyle(storage) }
        let length = (text as NSString).length
        textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        ruler.invalidateLines()
        updateTitle()
        if isPreviewing { preview?.show(markdown: text, fontSize: CGFloat(Preferences.shared.fontSize)) }
    }

    func documentRenamed() {
        updateTitle()
        sidebar.highlightCurrent()
    }

    /// 휴지통으로 보낸 노트의 창: 저장하지 않고 닫는다.
    func discardAndClose() {
        discarded = true
        saveWork?.cancel()
        note.fileURL = nil
        note.text = ""
        window?.close()
    }

    // MARK: - 창

    func showAndFocus() {
        guard let window else { return }
        NSApp.activate()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        window.makeKeyAndOrderFront(nil)
        if !isPreviewing { window.makeFirstResponder(textView) }
    }

    func setSidebar(visible: Bool, focusSearch: Bool = false) {
        guard let window else { return }
        if visible == isSidebarVisible {
            if visible, focusSearch { sidebar.focusSearch() }
            return
        }
        isSidebarVisible = visible
        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let frame = visible
            ? WindowGeometry.expandedForSidebar(window.frame, visibleFrame: visibleFrame)
            : WindowGeometry.collapsedFromSidebar(window.frame)
        window.minSize = NSSize(width: WindowGeometry.minimumSize.width + (visible ? WindowGeometry.sidebarWidth : 0),
                                height: WindowGeometry.minimumSize.height)
        sidebar.isHidden = !visible
        editorLeadingToRoot.isActive = !visible
        editorLeadingToSidebar.isActive = visible
        window.setFrame(frame, display: true)
        updateButtons()
        if visible {
            sidebar.reload()
            if focusSearch { sidebar.focusSearch() }
        } else if window.firstResponder is NSText || window.firstResponder === sidebar {
            window.makeFirstResponder(isPreviewing ? preview : textView)
        }
    }

    private func setPreview(_ on: Bool) {
        guard on != isPreviewing else { return }
        if on {
            guard note.format == .markdown else { NSSound.beep(); return }
            let view = preview ?? makePreview()
            view.show(markdown: textView.string, fontSize: CGFloat(Preferences.shared.fontSize))
            view.isHidden = false
            scrollView.isHidden = true
            isPreviewing = true
            window?.makeFirstResponder(view)
        } else {
            preview?.isHidden = true
            scrollView.isHidden = false
            isPreviewing = false
            window?.makeFirstResponder(textView)
        }
        updateButtons()
    }

    private func makePreview() -> PreviewView {
        let view = PreviewView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        editorContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: editorContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: editorContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: editorContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: editorContainer.bottomAnchor),
        ])
        preview = view
        return view
    }

    func setFloating(_ on: Bool) {
        isFloating = on
        window?.level = on ? .floating : .normal
        if pinButton != nil { updateButtons() }
    }

    // MARK: - 메뉴 동작(응답자 사슬로 들어온다)

    @objc func toggleSidebar(_ sender: Any?) {
        setSidebar(visible: !isSidebarVisible)
    }

    @objc func showNoteSearch(_ sender: Any?) {
        setSidebar(visible: true, focusSearch: true)
    }

    @objc func toggleNotePreview(_ sender: Any?) {
        setPreview(!isPreviewing)
    }

    @objc func toggleFloating(_ sender: Any?) {
        setFloating(!isFloating)
    }

    @objc func toggleNoteFormat(_ sender: Any?) {
        saveNow()
        NoteCenter.shared.setFormat(note.format.toggled, for: self)
        textView.format = note.format
        styler.format = note.format
        if let storage = textView.textStorage { styler.restyle(storage) }
        if note.format == .plainText, isPreviewing { setPreview(false) }
        updateButtons()
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(toggleSidebar(_:)):
            item.state = isSidebarVisible ? .on : .off
        case #selector(toggleNotePreview(_:)):
            item.state = isPreviewing ? .on : .off
            return note.format == .markdown
        case #selector(toggleFloating(_:)):
            item.state = isFloating ? .on : .off
        case #selector(toggleNoteFormat(_:)):
            item.title = note.format == .markdown ? "일반 텍스트로 바꾸기" : "마크다운으로 바꾸기"
        default:
            break
        }
        return true
    }

    // MARK: - NSWindowDelegate

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window else { return }
        var size = window.frame.size
        if isSidebarVisible { size.width -= WindowGeometry.sidebarWidth }
        Preferences.shared.savedWindowSize = size
    }

    func windowDidResignKey(_ notification: Notification) {
        if note.isDirty { saveNow() }
    }

    func windowWillClose(_ notification: Notification) {
        NoteCenter.shared.windowWillClose(self)
    }

    // 스냅숏 도구용
    var editorTextView: EditorTextView { textView }
    var sidebarView: SidebarView { sidebar }
}
