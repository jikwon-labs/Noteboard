import AppKit
import Combine
import Sparkle

/// Sparkle 자동 업데이트. 새 버전이 있으면 메뉴바 아이콘에 점을 찍고 메뉴에 설치 항목을 띄운다.
/// 메뉴바 앱이라 Sparkle 의 "부드러운 알림"을 쓴다: 앱이 앞에 있지 않을 때는 창을 띄우지 않고 표시만 한다.
final class UpdaterController: NSObject, ObservableObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    @Published private(set) var availableVersion: String?
    @Published private(set) var isAvailable = false

    private var controller: SPUStandardUpdaterController?

    override init() {
        super.init()
        let info = Bundle.main.infoDictionary ?? [:]
        let publicKey = (info["SUPublicEDKey"] as? String) ?? ""
        let feed = (info["SUFeedURL"] as? String) ?? ""
        // swift run 같은 개발 실행이나 서명 키 없는 빌드에서는 켜지 않는다.
        guard Bundle.main.bundleURL.pathExtension == "app", !publicKey.isEmpty, !feed.isEmpty else { return }
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: self)
        isAvailable = true
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
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    private func setAvailable(_ version: String?) {
        DispatchQueue.main.async { self.availableVersion = version }
    }

    // MARK: SPUUpdaterDelegate

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        setAvailable(item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        setAvailable(nil)
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
