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
/// settings window appears or Orbit comes back to the front.
enum LoginItemService {
    /// 上一次已知的注册状态；`nil` 表示还没问过 launchd。
    private static var lastKnownEnabled: Bool?

    static var isEnabled: Bool {
        lastKnownEnabled ?? reload()
    }

    /// 重新向 launchd 查询一次真实状态，并刷新缓存。
    ///
    /// Only `.enabled` counts as on. `.requiresApproval` means Orbit is
    /// registered but switched off under Login Items, and nothing launches at
    /// login in that state.
    @discardableResult
    static func reload() -> Bool {
        let enabled = SMAppService.mainApp.status == .enabled
        lastKnownEnabled = enabled
        return enabled
    }

    /// 注册或注销登录项，然后按 launchd 的真实状态刷新缓存。
    ///
    /// A successful `register()` is not the same as being enabled: if the user
    /// once turned Orbit off under Login Items, the registration is accepted
    /// and left waiting for approval. The cache used to record "on" anyway,
    /// so the switch showed on while nothing would launch. Now the real state
    /// is read back, and a registration waiting for approval opens the pane
    /// where it can be given.
    static func apply(enabled: Bool) throws {
        defer { reload() }
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
