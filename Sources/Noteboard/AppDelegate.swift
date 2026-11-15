import AppKit
import NoteboardCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let hotKey = GlobalHotKey()
    private(set) var updater: UpdaterController!
    private var statusItem: StatusItemController!
    private var settings: SettingsWindowController?
    private var observers: [NSObjectProtocol] = []
    /// 업데이트 설치로 다시 시작하거나 맥을 끌 때는 종료 확인을 묻지 않는다.
    private var skipQuitConfirmation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let dir = ProcessInfo.processInfo.environment["NOTEBOARD_SNAPSHOT_DIR"] {
            Snapshots.run(outputDirectory: URL(fileURLWithPath: dir), app: self)
            return
        }
        if ProcessInfo.processInfo.environment["NOTEBOARD_SELFTEST"] != nil {
            DispatchQueue.main.async { SelfTest.run(app: self) }
            return
        }
        NSApp.mainMenu = MainMenu.build()
        _ = NoteCenter.shared
        updater = UpdaterController()
        statusItem = StatusItemController(app: self)

        hotKey.onPress = { NoteCenter.shared.newNote() }
        registerHotKey()
        observers.append(NotificationCenter.default.addObserver(forName: .shortcutsChanged, object: nil, queue: .main) { [weak self] _ in
            self?.registerHotKey()
            MainMenu.applyShortcuts()
        })

        updater.onWillRelaunch = { [weak self] in self?.skipQuitConfirmation = true }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willPowerOffNotification,
                                                                            object: nil, queue: .main) { [weak self] _ in
            self?.skipQuitConfirmation = true
        })

        LoginItem.enableOnFirstLaunchIfInstalled()

        // 로그인 때 자동으로 켜진 게 아니면(직접 실행) 새 노트를 하나 띄운다.
        if !launchedAsLoginItem() {
            NoteCenter.shared.newNote()
        }
    }

    func setUpForSnapshots() {
        updater = UpdaterController()
    }

    func registerHotKey() {
        let shortcut = Preferences.shared.shortcut(.newNote)
        if !hotKey.register(shortcut) {
            NSLog("noteboard: 전역 단축키 \(shortcut.display) 등록 실패(다른 앱이 쓰는 중)")
        }
    }

    private func launchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NoteCenter.shared.newNote() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// ⌘Q 나 메뉴의 "종료"로 끌 때 한 번 묻는다. 끄면 전역 단축키도 멈추기 때문이다.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if skipQuitConfirmation { return .terminateNow }
        NSApp.activate()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        return Self.makeQuitAlert().runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }

    static func makeQuitAlert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "noteboard를 종료할까요?"
        alert.alertStyle = .informational
        alert.window.appearance = NSAppearance(named: .darkAqua)
        alert.addButton(withTitle: "종료")
        let cancel = alert.addButton(withTitle: "취소")
        cancel.keyEquivalent = "\u{1b}"
        return alert
    }

    func applicationWillTerminate(_ notification: Notification) {
        NoteCenter.shared.flushAll()
    }

    // MARK: - 메뉴 동작

    @objc func newNote(_ sender: Any?) {
        NoteCenter.shared.newNote()
    }

    @objc func showNoteList(_ sender: Any?) {
        NoteCenter.shared.newNote(showSidebar: true, focusSearch: true)
    }

    @objc func openSettings(_ sender: Any?) {
        if settings == nil { settings = SettingsWindowController(app: self) }
        settings?.show()
    }

    @objc func openStorageFolder(_ sender: Any?) {
        NSWorkspace.shared.open(NoteCenter.shared.library.folder)
    }

    @objc func checkForUpdates(_ sender: Any?) {
        updater.checkForUpdates()
    }

    @objc func increaseFontSize(_ sender: Any?) {
        Preferences.shared.fontSize += 1
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        Preferences.shared.fontSize -= 1
    }

    @objc func resetFontSize(_ sender: Any?) {
        Preferences.shared.fontSize = Preferences.defaultFontSize
    }

    @objc func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(checkForUpdates(_:)) { return updater?.isAvailable ?? false }
        return true
    }
}
