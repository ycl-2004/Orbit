//
//  OrbitUITests.swift
//  OrbitUITests
//

import XCTest

/// Orbit 是常驻菜单栏的 accessory 应用，没有主窗口，因此这里能做的 UI 断言只有
/// 一件事，但这件事很值得守住：它必须能启动，并且启动后留下来活着。
///
/// A crash on launch — a bad event tap, a missing entitlement, a status item that
/// throws — would otherwise be invisible to the unit tests, which never boot the
/// real app bundle.
final class OrbitUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testStaysAliveAsAMenuBarAccessory() throws {
        let app = XCUIApplication()
        app.launch()

        // Accessory 应用可能停在前台也可能停在后台，取决于欢迎窗口是否弹出，
        // 所以这里只断言"没有退出"，不断言具体是哪一种运行状态。
        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 10) || app.state == .runningBackground,
            "Orbit should still be running after launch, but its state was \(app.state.rawValue)."
        )

        // 给事件监听和菜单栏图标一点安置时间，再确认它没有随后崩掉。
        Thread.sleep(forTimeInterval: 1)
        XCTAssertNotEqual(app.state, .notRunning, "Orbit exited shortly after launching.")
    }

    @MainActor
    func testLaunchPerformance() throws {
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
