//
//  WindowVisibilityChecker.swift
//  Orbit
//

import CoreGraphics

/// 判断某个进程当前是否真的有窗口摆在屏幕上。
///
/// `NSRunningApplication` alone cannot answer this: a menu-bar helper, an app
/// that has closed its last window, and an app sitting on another Space all look
/// identical from there. The window server, on the other hand, knows — so this
/// asks it directly and applies the three filters that separate a real document
/// window from the invisible bookkeeping windows every app keeps around.
enum WindowVisibilityChecker {
    /// 一个窗口要算作"用户看得见"必须同时满足的条件。
    private enum Threshold {
        /// 只认普通窗口层；菜单栏、Dock、悬浮面板都在非 0 层。
        static let normalLayer = 0
        /// 完全透明的窗口在屏幕上等于不存在。
        static let minimumAlpha = 0.01
        /// 1×1 之类的探针窗口不算真窗口。
        static let minimumEdge: CGFloat = 1
    }

    static func hasVisibleWindow(processIdentifier: pid_t) -> Bool {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return false
        }

        return windows.contains { window in
            isVisibleWindow(window, ownedBy: processIdentifier)
        }
    }

    private static func isVisibleWindow(_ window: [String: Any], ownedBy pid: pid_t) -> Bool {
        guard window[kCGWindowOwnerPID as String] as? Int == Int(pid) else {
            return false
        }
        guard window[kCGWindowLayer as String] as? Int ?? 0 == Threshold.normalLayer else {
            return false
        }
        guard window[kCGWindowAlpha as String] as? Double ?? 1 > Threshold.minimumAlpha else {
            return false
        }
        guard let boundsDict = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
            return false
        }
        return bounds.width > Threshold.minimumEdge && bounds.height > Threshold.minimumEdge
    }
}
