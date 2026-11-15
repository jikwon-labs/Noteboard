import AppKit
import SwiftUI
import NoteboardCore

final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(app: AppDelegate) {
        let recorder = ShortcutRecorder(app: app)
        let view = SettingsView(prefs: .shared, updater: app.updater, recorder: recorder)
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "설정"
        window.styleMask = [.titled, .closable]
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        // 노트 창이 '항상 위에'면 설정 창이 가려지지 않게 같은 높이에 띄운다.
        window.level = .floating
        window.setContentSize(host.view.fittingSize)
        super.init(window: window)
        window.delegate = self
        recorder.window = window
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        NSApp.activate()
        if !NSApp.isActive { NSApp.activate(ignoringOtherApps: true) }
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }
}

/// 단축키 바꾸기: 버튼을 누르고 새 조합을 누른다. Esc 는 취소, ⌫ 는 기본값으로.
final class ShortcutRecorder: ObservableObject {
    @Published var recording: ShortcutAction?
    @Published var message: String?
    weak var window: NSWindow?
    private weak var app: AppDelegate?
    private var monitor: Any?

    init(app: AppDelegate) {
        self.app = app
    }

    func start(_ action: ShortcutAction) {
        stop()
        recording = action
        message = nil
        // 전역 단축키를 잠시 풀어야 같은 조합을 다시 누를 수 있다.
        app?.hotKey.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording != nil {
            recording = nil
            app?.registerHotKey()
        }
    }

    private static let reserved: Set<String> = ["q", "w", "c", "v", "x", "z", "a", "n", "f", "h", "m", ",", "g", "e", "0", "-", "="]

    private func handle(_ event: NSEvent) {
        guard let action = recording else { return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 53, flags.isEmpty { stop(); return }
        if event.keyCode == 51, flags.isEmpty {
            Preferences.shared.setShortcut(nil, for: action)
            stop()
            return
        }
        let key = Shortcut.asciiKey(forKeyCode: event.keyCode) ?? (event.charactersIgnoringModifiers ?? "").lowercased()
        let shortcut = Shortcut(keyCode: event.keyCode, key: key,
                                command: flags.contains(.command), option: flags.contains(.option),
                                control: flags.contains(.control), shift: flags.contains(.shift))
        guard shortcut.hasRequiredModifier, !key.isEmpty else {
            message = "⌘, ⌥, ⌃ 중 하나는 함께 눌러 주세요."
            return
        }
        if shortcut.command, !shortcut.option, !shortcut.control, Self.reserved.contains(key) {
            message = "\(shortcut.display) 는 기본 편집 단축키라 쓸 수 없습니다."
            return
        }
        if let other = ShortcutAction.allCases.first(where: { $0 != action && Preferences.shared.shortcut($0) == shortcut }) {
            message = "\(shortcut.display) 는 이미 '\(other.title)'에 쓰고 있습니다."
            return
        }
        if action == .newNote, let app {
            if !app.hotKey.register(shortcut) {
                message = "\(shortcut.display) 는 다른 앱이 이미 쓰고 있습니다."
                app.hotKey.unregister()
                return
            }
            app.hotKey.unregister()
        }
        Preferences.shared.setShortcut(shortcut, for: action)
        stop()
    }
}

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var updater: UpdaterController
    @ObservedObject var recorder: ShortcutRecorder
    @State private var loginEnabled = LoginItem.isEnabled
    @State private var loginError: String?

    private var folderDisplay: String {
        let path = prefs.storageFolder.path
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    var body: some View {
        Form {
            Section("일반") {
                LabeledContent {
                    HStack(spacing: 6) {
                        Button("Finder에서 보기") { NSWorkspace.shared.open(prefs.storageFolder) }
                        Button("변경…") { chooseFolder() }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("저장 폴더")
                        Text(folderDisplay)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Toggle("로그인 시 자동 실행", isOn: Binding(get: { loginEnabled }, set: setLogin))
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }
            Section("편집") {
                Picker("새 노트 기본 포맷", selection: $prefs.defaultFormat) {
                    Text("마크다운").tag(NoteFormat.markdown)
                    Text("텍스트").tag(NoteFormat.plainText)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                Stepper(value: $prefs.fontSize, in: Preferences.fontSizeRange, step: 1) {
                    HStack {
                        Text("글자 크기")
                        Spacer()
                        Text("\(Int(prefs.fontSize))pt").monospacedDigit().foregroundStyle(.secondary)
                    }
                }
            }
            Section("창") {
                Toggle("새 창을 항상 위에 띄우기", isOn: $prefs.newWindowsFloat)
            }
            Section {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        Button {
                            if recorder.recording == action { recorder.stop() } else { recorder.start(action) }
                        } label: {
                            Text(recorder.recording == action ? "새 조합 입력…" : prefs.shortcut(action).display)
                                .frame(minWidth: 84)
                                .monospacedDigit()
                        }
                        .accessibilityLabel("\(action.title) 단축키 바꾸기")
                    }
                }
            } header: {
                Text("단축키")
            } footer: {
                Text(recorder.message ?? "버튼을 누르고 새 조합을 누르세요. Esc 취소, ⌫ 기본값.")
                    .font(.caption)
                    .foregroundStyle(recorder.message == nil ? Color.secondary : Color.orange)
            }
            Section("업데이트") {
                Toggle("자동으로 업데이트 확인", isOn: Binding(get: { updater.automaticallyChecks },
                                                     set: { updater.automaticallyChecks = $0 }))
                    .disabled(!updater.isAvailable)
                LabeledContent {
                    if let version = updater.availableVersion {
                        Button("\(version) 설치…") { updater.checkForUpdates() }
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("지금 확인") { updater.checkForUpdates() }
                            .disabled(!updater.isAvailable)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("현재 버전 \(AppVersion.version)")
                        if let version = updater.availableVersion {
                            Text("새 버전 \(version)이 있습니다").font(.caption).foregroundStyle(.secondary)
                        } else if !updater.isAvailable {
                            Text("개발 빌드에서는 업데이트를 쓸 수 없습니다").font(.caption).foregroundStyle(.secondary)
                        } else if updater.missingToken {
                            Text("업데이트를 받으려면 터미널에서 gh auth login 이 필요합니다").font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { recorder.stop() }
    }

    private func setLogin(_ on: Bool) {
        do {
            try LoginItem.set(on)
            loginError = nil
        } catch {
            loginError = "바꾸지 못했습니다: \(error.localizedDescription)"
        }
        loginEnabled = LoginItem.isEnabled
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "선택"
        panel.message = "노트를 저장할 폴더를 고르세요"
        panel.directoryURL = prefs.storageFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if url.standardizedFileURL == prefs.storageFolder.standardizedFileURL { return }

        var move = false
        if !NoteCenter.shared.summaries.isEmpty {
            let alert = NSAlert()
            alert.messageText = "기존 노트를 새 폴더로 옮길까요?"
            alert.informativeText = "노트 \(NoteCenter.shared.summaries.count)개가 지금 폴더에 있습니다. 옮기지 않으면 지금 폴더에 그대로 남고 목록에는 보이지 않습니다."
            alert.addButton(withTitle: "옮기기")
            alert.addButton(withTitle: "그대로 두기")
            alert.addButton(withTitle: "취소")
            switch alert.runModal() {
            case .alertFirstButtonReturn: move = true
            case .alertSecondButtonReturn: move = false
            default: return
            }
        }
        NoteCenter.shared.changeFolder(to: url, moveExisting: move)
    }
}
