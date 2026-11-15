import Foundation
import ServiceManagement

/// 로그인 시 자동 실행.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// 응용 프로그램 폴더에서 처음 실행했을 때 한 번만 켠다(개발 빌드 경로가 등록되지 않게).
    static func enableOnFirstLaunchIfInstalled() {
        let key = "didSetUpLoginItem"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: key) else { return }
        let path = Bundle.main.bundlePath
        guard path.hasPrefix("/Applications/") || path.hasPrefix(NSHomeDirectory() + "/Applications/") else { return }
        try? set(true)
        defaults.set(true, forKey: key)
    }
}
