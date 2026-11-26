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
        // 照常启动，但不弹授权框和欢迎页，设置也写进测试专用的域。
        app.launchArguments += ["-OrbitUITesting"]
        app.launch()

        // 前台还是后台都算启动成功：accessory 应用通常停在后台。等到其中之一为止，
        // 而不是死等某一种状态把超时耗满。
        let running = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                app.state == .runningForeground || app.state == .runningBackground
            },
            object: nil
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [running], timeout: 10),
            .completed,
            "Orbit should be running after launch, but its state was \(app.state.rawValue)."
        )

        // 事件监听和菜单栏图标装好之后，它不能随后崩掉。
        let exited = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in app.state == .notRunning },
            object: nil
        )
        exited.isInverted = true
        XCTAssertEqual(
            XCTWaiter().wait(for: [exited], timeout: 2),
            .completed,
            "Orbit exited shortly after launching."
        )

        app.terminate()
    }
}
