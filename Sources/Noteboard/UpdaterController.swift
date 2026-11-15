import AppKit
import Combine
import Sparkle

/// Sparkle 자동 업데이트. 새 버전이 있으면 메뉴바 아이콘에 점을 찍고 메뉴에 설치 항목을 띄운다.
/// 메뉴바 앱이라 Sparkle 의 "부드러운 알림"을 쓴다: 앱이 앞에 있지 않을 때는 창을 띄우지 않고 표시만 한다.
///
/// 코드 레포(jikwon-labs/Noteboard)가 비공개라, 업데이트 정보와 파일을 받을 때 GitHub 토큰을 붙인다.
/// 토큰은 앱에 넣지 않고 이 맥에 로그인된 `gh` 에서 그때그때 읽는다(`gh auth token`).
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var isAvailable = false
    /// gh 로그인이 없어 토큰을 못 읽었다(업데이트 확인이 실패한다).
    @Published private(set) var missingToken = false

    private var controller: SPUStandardUpdaterController?
    /// 업데이트를 설치하려고 앱을 다시 시작하기 직전(종료 확인을 건너뛰게 한다).
    var onWillRelaunch: (() -> Void)?

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let publicKey = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        // swift run 같은 개발 실행이나 서명 키 없는 빌드에서는 켜지 않는다.
        guard Bundle.main.bundleURL.pathExtension == "app", !publicKey.isEmpty, !feed.isEmpty else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
        self.controller = controller
        isAvailable = true
        refreshToken { [weak self] in
            guard let self else { return }
            controller.startUpdater()
            if ProcessInfo.processInfo.environment["NOTEBOARD_UPDATE_PROBE"] != nil {
                NSLog("noteboard: 업데이트 확인 시험 시작")
                controller.updater.checkForUpdatesInBackground()
            }
            _ = self
        }
    }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }

    func checkForUpdates() {
        guard let controller else { return }
        refreshToken {
            NSApp.activate()
            controller.checkForUpdates(nil)
        }
    }

    /// gh 에서 토큰을 읽어 Sparkle 요청 헤더에 넣는다.
    private func refreshToken(then done: @escaping () -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let token = GitHubToken.read()
            DispatchQueue.main.async {
                self.missingToken = token == nil
                var headers = ["Accept": "application/octet-stream"]
                if let token { headers["Authorization"] = "Bearer \(token)" }
                self.controller?.updater.httpHeaders = headers
                done()
            }
        }
    }

    private func setAvailable(_ version: String?) {
        DispatchQueue.main.async { self.availableVersion = version }
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        NSLog("noteboard: 새 버전 발견 \(item.displayVersionString) (build \(item.versionString))")
        setAvailable(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        NSLog("noteboard: 최신 버전이다")
        setAvailable(nil)
    }

    func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
        onWillRelaunch?()
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("noteboard: 업데이트 확인 실패 \(error.localizedDescription)")
    }

    // MARK: SPUStandardUserDriverDelegate (부드러운 알림)

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        setAvailable(update.displayVersionString)
    }
}

/// 이 맥에 로그인된 GitHub CLI 의 토큰. Finder 에서 띄운 앱은 PATH 가 짧아서 흔한 설치 경로를 직접 찾는다.
enum GitHubToken {
    static func read() -> String? {
        let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        guard let gh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = ["auth", "token", "--hostname", "github.com"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
