//
//  DragState.swift
//  Orbit
//

import Foundation

/// 一次文件拖放在环形界面上所处的阶段。
///
/// The ring only ever needs to know *which* affordance the center should show,
/// not which URLs are in flight — the dropped items are read from the pasteboard
/// providers at drop time, not tracked while hovering. Keeping the payload out
/// of the state means hover updates stay cheap and can never disagree with what
/// is actually dropped.
enum FileDropPhase: Equatable {
    /// 没有文件悬停在窗口上。
    case idle
    /// 文件已进入窗口，中心显示 AirDrop 分享。
    case hovering
    /// 悬停已超过阈值，中心变成黑洞（松手扔进废纸篓）。
    case trashArmed
    /// 已经松手，正在读取并处理这些文件。
    case completing

    /// 中心区域是否正在承接一次悬停中的拖放。
    ///
    /// `.completing` 不算 —— 那时文件已经离手，中心该停止响应新的悬停逻辑。
    var isReceiving: Bool {
        self == .hovering || self == .trashArmed
    }
}
