//
//  OrbitNotifications.swift
//  Orbit
//

import Foundation

/// Orbit 内部各层之间的广播。
///
/// The event tap lives outside SwiftUI and must not reach into window controllers
/// directly, so everything it observes is republished as a notification and the
/// UI layer subscribes. Names are reverse-DNS so they can never collide with a
/// notification posted by AppKit or by another process's injected bundle.
extension Notification.Name {
    /// 触发键已按住足够久，请把环形界面唤出来。
    ///
    /// `object` 里装着一个 `NSValue` 包裹的屏幕坐标点，表示环该以哪里为中心。
    static let orbitSummonRequested = Notification.Name("app.orbit.summonRequested")

    /// 触发键已松开。
    static let orbitTriggerReleased = Notification.Name("app.orbit.triggerReleased")

    /// 环形界面显示期间按下了一个被拦截的按键。
    static let orbitKeyboardCommand = Notification.Name("app.orbit.keyboardCommand")
}

/// 环形界面打开时，键盘事件被翻译成的动作。
enum OrbitKeyboardCommand: String {
    case next
    case previous
    case activate
    case cancel
    /// 清空当前选择，但不关闭环形界面。
    case deselect
    /// 在预览面板里，于选中应用的多个窗口之间移动。
    case nextWindow
    case previousWindow
    case number
    case letter
}
