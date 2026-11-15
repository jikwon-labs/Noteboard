import AppKit
import NoteboardCore

/// 사이드바: 검색창 + 노트 목록. 한 번 누르면 열고, 두 번 누르면 제목을 바꾼다.
final class SidebarView: NSView, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSTextFieldDelegate, NSMenuDelegate {
    weak var controller: NoteWindowController?

    let searchField = NSSearchField()
    private let tableView = SidebarTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private var items: [NoteSummary] = []
    private var pendingOpen: DispatchWorkItem?
    private var renaming: (row: Int, url: URL)?
    private var reloadDeferred = false
    private var observer: NSObjectProtocol?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = Theme.sidebarBackground.cgColor

        let border = NSView()
        border.wantsLayer = true
        border.layer?.backgroundColor = Theme.separator.cgColor

        searchField.placeholderString = "제목, 날짜, 내용 검색"
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .default
        searchField.font = .systemFont(ofSize: 12)
        searchField.setAccessibilityLabel("노트 검색")

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("note"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .plain
        tableView.backgroundColor = .clear
        tableView.rowHeight = 40
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.onReturn = { [weak self] in self?.openSelected(forceNewWindow: false) }
        tableView.onDelete = { [weak self] in self?.trashSelected() }
        let menu = NSMenu()
        menu.delegate = self
        tableView.menu = menu

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 6, right: 0)

        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.textColor = Theme.secondaryText
        emptyLabel.alignment = .center

        for v in [border, searchField, scrollView, emptyLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 1),

            searchField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: border.leadingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),

            emptyLabel.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 18),
            emptyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            emptyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        observer = NotificationCenter.default.addObserver(forName: .notesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.reload()
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// 창에 붙인 뒤 부른다: 검색창을 제목 표시줄 바로 아래에 둔다.
    func attachSearchTop(to anchor: NSLayoutYAxisAnchor) {
        searchField.topAnchor.constraint(equalTo: anchor, constant: 4).isActive = true
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    // MARK: - 목록

    func reload() {
        if renaming != nil {
            reloadDeferred = true
            return
        }
        guard !isHidden else { return }
        items = NoteSearch.filter(NoteCenter.shared.summaries, query: searchField.stringValue, now: Date())
        tableView.reloadData()
        highlightCurrent()
        let hasQuery = !searchField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        emptyLabel.stringValue = hasQuery ? "검색 결과 없음" : "노트가 없습니다"
        emptyLabel.isHidden = !items.isEmpty
    }

    func highlightCurrent() {
        guard let path = controller?.note.fileURL?.standardizedFileURL.path,
              let row = items.firstIndex(where: { $0.id == path }) else {
            tableView.deselectAll(nil)
            return
        }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        tableView.scrollRowToVisible(row)
    }

    func focusSearch() {
        window?.makeFirstResponder(searchField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("NoteRowCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NoteRowCell) ?? NoteRowCell()
        cell.identifier = id
        cell.configure(items[row], now: Date())
        cell.titleField.delegate = self
        return cell
    }

    // MARK: - 누르기

    @objc private func rowClicked() {
        let row = tableView.clickedRow
        guard row >= 0, row < items.count, renaming == nil else { return }
        pendingOpen?.cancel()
        let summary = items[row]
        // 두 번 누르기(제목 바꾸기)와 구분하려고 아주 잠깐 기다렸다가 연다.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            NoteCenter.shared.open(summary, from: self.controller)
            self.highlightCurrent()
        }
        pendingOpen = work
        DispatchQueue.main.asyncAfter(deadline: .now() + min(NSEvent.doubleClickInterval, 0.28), execute: work)
    }

    @objc private func rowDoubleClicked() {
        pendingOpen?.cancel()
        pendingOpen = nil
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        beginRename(row: row)
    }

    private func openSelected(forceNewWindow: Bool) {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        NoteCenter.shared.open(items[row], from: controller, forceNewWindow: forceNewWindow)
        highlightCurrent()
    }

    private func trashSelected() {
        let row = tableView.selectedRow
        guard row >= 0, row < items.count else { return }
        NoteCenter.shared.trash(items[row].url)
    }

    // MARK: - 제목 바꾸기

    private func beginRename(row: Int) {
        guard let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NoteRowCell else { return }
        renaming = (row, items[row].url)
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        cell.beginEditing(title: items[row].title)
        window?.makeFirstResponder(cell.titleField)
        cell.titleField.currentEditor()?.selectAll(nil)
    }

    private func endRename(commit: Bool) {
        guard let current = renaming else { return }
        renaming = nil
        let cell = tableView.view(atColumn: 0, row: current.row, makeIfNecessary: false) as? NoteRowCell
        let newTitle = cell?.titleField.stringValue ?? ""
        cell?.endEditing()
        if commit, current.row < items.count, newTitle != items[current.row].title {
            NoteCenter.shared.rename(current.url, to: newTitle)
        } else {
            reload()
        }
        if reloadDeferred {
            reloadDeferred = false
            reload()
        }
        window?.makeFirstResponder(tableView)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        guard let field = obj.object as? NSTextField, field !== searchField, renaming != nil else { return }
        endRename(commit: true)
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSSearchField) === searchField { reload() }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === searchField {
            switch selector {
            case #selector(NSResponder.cancelOperation(_:)):
                if textView.hasMarkedText() { return false }
                if searchField.stringValue.isEmpty {
                    window?.performClose(nil)
                } else {
                    searchField.stringValue = ""
                    reload()
                }
                return true
            case #selector(NSResponder.insertNewline(_:)):
                if !items.isEmpty {
                    NoteCenter.shared.open(items[0], from: controller)
                    highlightCurrent()
                }
                return true
            case #selector(NSResponder.moveDown(_:)):
                if !items.isEmpty {
                    window?.makeFirstResponder(tableView)
                    tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
                }
                return true
            default:
                return false
            }
        }
        // 제목 바꾸는 칸
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            if textView.hasMarkedText() { return false }
            endRename(commit: false)
            return true
        }
        return false
    }

    // MARK: - 오른쪽 클릭 메뉴

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < items.count else { return }
        menu.addItem(withTitle: "열기", action: #selector(menuOpen(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "새 창에서 열기", action: #selector(menuOpenNewWindow(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "제목 바꾸기", action: #selector(menuRename(_:)), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Finder에서 보기", action: #selector(menuReveal(_:)), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "휴지통으로 이동", action: #selector(menuTrash(_:)), keyEquivalent: "").target = self
        for item in menu.items { item.tag = row }
    }

    @objc private func menuOpen(_ sender: NSMenuItem) {
        guard sender.tag < items.count else { return }
        NoteCenter.shared.open(items[sender.tag], from: controller)
        highlightCurrent()
    }

    @objc private func menuOpenNewWindow(_ sender: NSMenuItem) {
        guard sender.tag < items.count else { return }
        NoteCenter.shared.open(items[sender.tag], from: controller, forceNewWindow: true)
        highlightCurrent()
    }

    @objc private func menuRename(_ sender: NSMenuItem) {
        guard sender.tag < items.count else { return }
        beginRename(row: sender.tag)
    }

    @objc private func menuReveal(_ sender: NSMenuItem) {
        guard sender.tag < items.count else { return }
        NoteCenter.shared.revealInFinder(items[sender.tag].url)
    }

    @objc private func menuTrash(_ sender: NSMenuItem) {
        guard sender.tag < items.count else { return }
        NoteCenter.shared.trash(items[sender.tag].url)
    }
}

/// Return 으로 열기, ⌘⌫ 로 휴지통.
final class SidebarTableView: NSTableView {
    var onReturn: (() -> Void)?
    var onDelete: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            onReturn?()
            return
        }
        if event.keyCode == 51, event.modifierFlags.contains(.command) {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}

final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Theme.rowSelection.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 0), xRadius: 6, yRadius: 6).fill()
    }

    override var isEmphasized: Bool {
        get { false }
        set {}
    }
}

/// 목록 한 줄: 위는 제목(없으면 첫 줄), 아래는 날짜 · 첫 줄.
final class NoteRowCell: NSTableCellView {
    let titleField = NSTextField(labelWithString: "")
    private let subtitleField = NSTextField(labelWithString: "")
    private var isTitled = false

    init() {
        super.init(frame: .zero)
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.maximumNumberOfLines = 1
        subtitleField.font = .systemFont(ofSize: 11)
        subtitleField.textColor = Theme.secondaryText
        subtitleField.lineBreakMode = .byTruncatingTail
        subtitleField.maximumNumberOfLines = 1
        let stack = NSStackView(views: [titleField, subtitleField])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
            subtitleField.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ summary: NoteSummary, now: Date) {
        isTitled = !summary.title.isEmpty
        titleField.stringValue = summary.displayTitle
        titleField.font = .systemFont(ofSize: 12.5, weight: isTitled ? .semibold : .regular)
        titleField.textColor = isTitled ? Theme.strongText : Theme.text
        subtitleField.stringValue = summary.subtitle(now: now)
        setAccessibilityLabel("\(summary.displayTitle), \(summary.subtitle(now: now))")
    }

    func beginEditing(title: String) {
        titleField.isEditable = true
        titleField.isSelectable = true
        titleField.isBordered = false
        titleField.drawsBackground = true
        titleField.backgroundColor = NSColor(hex: 0x0F0F10)
        titleField.focusRingType = .default
        titleField.placeholderString = "제목 없음"
        titleField.stringValue = title
        titleField.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleField.textColor = Theme.strongText
    }

    func endEditing() {
        titleField.isEditable = false
        titleField.isSelectable = false
        titleField.drawsBackground = false
        titleField.placeholderString = nil
    }
}
