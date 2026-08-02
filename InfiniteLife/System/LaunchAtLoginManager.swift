import Foundation
import ServiceManagement

enum LaunchAtLoginManager {
    static func setEnabled(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // 正式なアプリバンドルとして配置されていない場合、登録に失敗することがある。
                NSLog("InfiniteLife: ログイン時の起動設定に失敗しました: \(error.localizedDescription)")
            }
        }
    }

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }
}
