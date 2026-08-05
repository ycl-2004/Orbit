//
//  LoginItemService.swift
//  Orbit
//

import ServiceManagement

/// 开机自启开关，包装 `SMAppService`。
///
/// `SMAppService.mainApp.status` talks to `launchd` on every read, so the
/// settings window would hit it once per SwiftUI redraw. The last known status
/// is therefore cached and only re-read when something could actually have
/// changed it: an explicit toggle, or an explicit `reload()` when the
/// settings window appears.
enum LoginItemService {
    /// 上一次已知的注册状态；`nil` 表示还没问过 launchd。
    private static var lastKnownEnabled: Bool?

    static var isEnabled: Bool {
        lastKnownEnabled ?? reload()
    }

    /// 重新向 launchd 查询一次真实状态，并刷新缓存。
    @discardableResult
    static func reload() -> Bool {
        let enabled = SMAppService.mainApp.status == .enabled
        lastKnownEnabled = enabled
        return enabled
    }

    /// 注册或注销登录项。
    ///
    /// 只有在 `SMAppService` 没有抛错时才更新缓存 —— 抛错说明 launchd 没有接受
    /// 这次改动，此时缓存必须保持原样，否则 UI 会显示一个并未生效的开关状态。
    static func apply(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        lastKnownEnabled = enabled
    }
}
