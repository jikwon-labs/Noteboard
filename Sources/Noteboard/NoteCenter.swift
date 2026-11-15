import AppKit
import NoteboardCore

/// 앱 전체의 노트 관리: 저장 폴더, 목록, 열린 창들, 저장·이름 변경·삭제.
final class NoteCenter {
    static let shared = NoteCenter()

    private(set) var library: NoteLibrary
    private(set) var summaries: [NoteSummary] = []
    private(set) var controllers: [NoteWindowController] = []
    private var watcher: FolderWatcher!
    private var reloadWork: DispatchWorkItem?

    private init() {
        library = NoteLibrary(folder: Preferences.shared.storageFolder)
        try? library.ensureFolder()
        watcher = FolderWatcher { [weak self] in self?.folderChanged() }
        watcher.watch(library.folder)
        reload()
    }

    // MARK: - 목록

    func reload() {
        summaries = library.list()
        NotificationCenter.default.post(name: .notesChanged, object: nil)
    }

    private func folderChanged() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.reload()
            for c in self.controllers { c.checkExternalChange() }
        }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    // MARK: - 창

    /// 단축키로 여는 새 창. 사이드바는 닫힌 상태로 연다.
    @discardableResult
    func newNote(showSidebar: Bool = false, focusSearch: Bool = false) -> NoteWindowController {
        let controller = NoteWindowController(note: NoteDocument(format: Preferences.shared.defaultFormat))
        place(controller)
        controllers.append(controller)
        controller.showAndFocus()
        if showSidebar { controller.setSidebar(visible: true, focusSearch: focusSearch) }
        return controller
    }

    /// 마우스가 있는 화면 가운데에, 이미 창이 있으면 계단식으로.
    private func place(_ controller: NoteWindowController) {
        guard let window = controller.window else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        let visible = screen.visibleFrame
        let size = Preferences.shared.savedWindowSize.map { WindowGeometry.clamped($0, to: visible) }
            ?? WindowGeometry.defaultSize(screenFrame: screen.frame)
        let occupied = controllers.compactMap { $0.window?.frame.origin }
        let origin = WindowGeometry.origin(for: size, in: visible, occupied: occupied)
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }

    func controller(for url: URL) -> NoteWindowController? {
        let key = url.standardizedFileURL.path
        return controllers.first { $0.note.fileURL?.standardizedFileURL.path == key }
    }

    /// 사이드바에서 노트를 골랐을 때. 이미 열려 있으면 그 창을, 지금 창이 비어 있으면 그 창에, 아니면 새 창에.
    func open(_ summary: NoteSummary, from source: NoteWindowController?, forceNewWindow: Bool = false) {
        if let existing = controller(for: summary.url) {
            existing.showAndFocus()
            return
        }
        guard let text = try? NoteLibrary(folder: summary.url.deletingLastPathComponent()).read(summary.url) else {
            NSSound.beep()
            reload()
            return
        }
        let note = NoteDocument(url: summary.url, title: summary.title, format: summary.format, text: text,
                                    created: summary.created, modified: summary.modified)
        if !forceNewWindow, let source, source.note.isPristine {
            source.load(note)
            source.showAndFocus()
            return
        }
        let controller = NoteWindowController(note: note)
        place(controller)
        controllers.append(controller)
        controller.showAndFocus()
    }

    // MARK: - 저장

    private func libraryFor(_ url: URL) -> NoteLibrary {
        NoteLibrary(folder: url.deletingLastPathComponent())
    }

    func save(_ note: NoteDocument) {
        do {
            if let url = note.fileURL {
                guard note.isDirty else { return }
                try libraryFor(url).write(note.text, to: url)
            } else {
                // 아무것도 안 쓴 창은 파일을 만들지 않는다.
                if note.isBlank { return }
                note.fileURL = try library.create(text: note.text, title: note.title,
                                                      format: note.format, created: note.created)
            }
            note.markSaved(modificationDate: note.fileURL.flatMap { library.modificationDate(of: $0) })
        } catch {
            NSLog("noteboard: 저장 실패 \(error)")
            return
        }
        scheduleReload()
    }

    private func scheduleReload() {
        reloadWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.reload() }
        reloadWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// 사이드바에서 제목을 바꿨을 때. 파일 이름이 곧 제목이다.
    func rename(_ url: URL, to title: String) {
        let open = controller(for: url)
        open?.saveNow()
        do {
            let format = NoteFormat(fileExtension: url.pathExtension) ?? .markdown
            let newURL = try libraryFor(url).rename(url, title: title, format: format)
            if let open {
                open.note.fileURL = newURL
                open.note.title = NoteNaming.title(fromStem: newURL.deletingPathExtension().lastPathComponent)
                open.documentRenamed()
            }
        } catch {
            presentError("제목을 바꾸지 못했습니다", error)
        }
        reload()
    }

    /// 포맷(MD ↔ TXT)을 바꾸면 확장자도 바꾼다.
    func setFormat(_ format: NoteFormat, for controller: NoteWindowController) {
        let note = controller.note
        note.format = format
        guard let url = note.fileURL else { return }
        do {
            note.fileURL = try libraryFor(url).rename(url, title: note.title, format: format)
        } catch {
            presentError("포맷을 바꾸지 못했습니다", error)
        }
        reload()
    }

    func trash(_ url: URL) {
        if let open = controller(for: url) { open.discardAndClose() }
        do {
            try libraryFor(url).trash(url)
        } catch {
            presentError("휴지통으로 옮기지 못했습니다", error)
        }
        reload()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// 창을 닫을 때: 마지막 내용을 저장하고, 아무것도 안 쓴 노트는 지운다.
    func windowWillClose(_ controller: NoteWindowController) {
        finish(controller)
        controllers.removeAll { $0 === controller }
        scheduleReload()
    }

    private func finish(_ controller: NoteWindowController) {
        controller.saveNow()
        if let url = controller.note.fileURL, controller.note.isBlank {
            try? libraryFor(url).deleteIfBlank(url)
        }
    }

    /// 앱을 끌 때.
    func flushAll() {
        for c in controllers { finish(c) }
    }

    // MARK: - 저장 폴더 바꾸기

    func changeFolder(to folder: URL, moveExisting: Bool) {
        for c in controllers { c.saveNow() }
        do {
            let target = NoteLibrary(folder: folder)
            try target.ensureFolder()
            if moveExisting {
                let mapping = try library.moveAll(to: folder)
                for c in controllers {
                    if let url = c.note.fileURL?.standardizedFileURL, let moved = mapping[url] {
                        c.note.fileURL = moved
                    }
                }
            }
            library = target
            Preferences.shared.storageFolder = target.folder
            watcher.watch(target.folder)
        } catch {
            presentError("저장 폴더를 바꾸지 못했습니다", error)
        }
        reload()
    }

    private func presentError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }
}
