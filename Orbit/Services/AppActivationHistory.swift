//
//  AppActivationHistory.swift
//  Orbit
//
//  Remembers which apps were used most recently, so the ring can show the
//  twelve that matter instead of the twelve that sort first.
//

import AppKit
import CoreGraphics

/// 谁最近被用过。
///
/// 环上只放得下 `maxVisibleApps` 张卡，而以前那份列表是按名字排好之后直接截断
/// 的 —— 也就是说开着二十个应用时，名字排在后面的那些永远上不了环，而且界面上
/// 没有任何地方说它们被藏起来了。截断必须按"最近用过"来，排序也一样：最常做的
/// 事情是切回刚才那个应用，它就该是第一张卡。
///
/// 两个信号叠在一起用：
///
/// - `NSWorkspace` 的激活通知是准的，但 Orbit 刚启动时它一条记录都没有。
/// - 窗口服务的 z 序（前后叠放顺序）第一次唤出就能拿到，而且前后关系本身就
///   约等于"谁刚被抬到前面"。
///
/// 所以启动时先用 z 序把历史铺满，之后由通知接管。两者都答不上来的应用排在最
/// 后，按名字，跟以前一样。
@MainActor
final class AppActivationHistory {
    static let shared = AppActivationHistory()

    /// 最近使用在前。存 bundle id，因为 pid 每次启动都会变。
    private var order: [String] = []
    private var observer: NSObjectProtocol?
    /// 订阅是异步挂上的，所以不能再拿 `observer` 当"启动过了没"的标记。
    private var hasStarted = false

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // 窗口的前后顺序当场就能拿到，所以启动路径上只做这一件事。
        seedFromWindowOrder()

        // 订阅推迟到启动之后。
        //
        // 在 `applicationDidFinishLaunching` 里就挂上 workspace 的激活通知，会让
        // Orbit 启动后进不了前台 —— UI 测试里 `XCTApplicationLaunchMetric` 因此
        // 完全无法激活它，而 `testStaysAliveAsAMenuBarAccessory` 从 2.7 秒变成撞
        // 满 10 秒超时再退回后台态。这里本来也没有抢这一拍的理由：环上的顺序由
        // 上面那份 z 序打底，第一次切换应用还没发生。
        DispatchQueue.main.async { [weak self] in
            self?.subscribe()
        }
    }

    private func subscribe() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication else { return }
            // 跟这个项目里别处一样用 `Task { @MainActor }` 而不是
            // `assumeIsolated` —— 后者一旦判断失手就是 trap，而这段代码每切一次
            // 应用就跑一次，崩在这里等于崩在所有地方。
            Task { @MainActor in
                AppActivationHistory.shared.record(app)
            }
        }
    }

    /// 越小越近。没有记录的应用返回 `nil`，由调用方决定怎么排它们。
    func rank(of identity: String) -> Int? {
        order.firstIndex(of: identity)
    }

    private func record(_ app: NSRunningApplication) {
        // Orbit 自己被激活（比如打开设置窗口）不该把它挤到第一位。
        guard let identity = app.bundleIdentifier,
              identity != Bundle.main.bundleIdentifier else { return }
        order.removeAll { $0 == identity }
        order.insert(identity, at: 0)
    }

    /// 用窗口的前后叠放顺序补一份初始历史。
    ///
    /// `CGWindowListCopyWindowInfo` 的 `.optionOnScreenOnly` 是按前到后返回的，
    /// 所以第一次见到某个 pid 的位置，就是那个应用离用户最近的那扇窗的位置。
    /// 最小化的、在别的 Space 的窗口不在这份表里 —— 那正好，它们本来就不该排在
    /// 屏幕上正摆着的窗口前面。
    private func seedFromWindowOrder() {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        var seen: Set<pid_t> = []
        for window in windows where WindowServerInspector.qualifiesAsWindow(window) {
            guard let raw = window[kCGWindowOwnerPID as String] as? Int else { continue }
            let pid = pid_t(raw)
            guard seen.insert(pid).inserted else { continue }
            guard let identity = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
                  identity != Bundle.main.bundleIdentifier,
                  !order.contains(identity) else { continue }
            order.append(identity)
        }
    }
}
