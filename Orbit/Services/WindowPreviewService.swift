//
//  WindowPreviewService.swift
//  Orbit
//
//  Static window thumbnails for the ring's preview panel. Capture needs the
//  Screen Recording permission, which is separate from the Accessibility
//  permission the ring itself needs — the preview is opt-in for that reason.
//

import AppKit
import ApplicationServices
import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import VideoToolbox

/// Everything Orbit knows about one window at the moment it was listed, kept
/// so the window can be found again when the user picks it.
///
/// A title alone is not an identity: an app can have several windows carrying
/// the same one, and the string ScreenCaptureKit reports is not always the
/// string Accessibility reports for the same window. The frame settles both.
struct WindowTarget: Sendable, Equatable {
    let id: CGWindowID
    let title: String
    /// CoreGraphics global coordinates, top-left origin — the space
    /// `kAXPositionAttribute` answers in too, so the two compare directly.
    let frame: CGRect
}

/// 唤出那一刻用户正看着的那扇窗。
///
/// 预览面板把它藏起来：它就是此刻占满屏幕的那一扇，列出来只会占掉一个位置，
/// 而选中它等于什么也没发生。
struct CurrentWindow: Sendable, Equatable {
    let processIdentifier: pid_t
    let id: CGWindowID

    /// 只在它自己的应用里藏 —— 窗口号是全系统唯一的，但这里要的是「你正用的
    /// 那个应用里的那一扇」，别的应用不该受影响。
    func hiddenWindow(inAppWith pid: pid_t) -> CGWindowID? {
        processIdentifier == pid ? id : nil
    }
}

struct WindowPreview: Identifiable, Sendable {
    let id: CGWindowID
    let title: String
    /// Where the window sat when it was listed. Only used to find it again.
    let frame: CGRect
    /// Nil when the window could not be captured and nothing was cached —
    /// the panel then falls back to showing the title alone.
    let image: CGImage?
    let aspectRatio: CGFloat
    /// 这张图是按哪个像素密度截的。跟着图走，因为只有捕获它的那次调用知道
    /// 圆环当时在哪块屏上 —— 展示它的卡片再去问 `NSScreen.main` 就会答错。
    let scale: CGFloat
    /// Luminance spread; near zero means the window rendered as a flat block.
    let contentVariance: Double
    /// True when the image came from cache because a fresh capture failed.
    let isStale: Bool

    var target: WindowTarget {
        WindowTarget(id: id, title: title, frame: frame)
    }
}

@MainActor
final class WindowPreviewService {
    static let shared = WindowPreviewService()

    /// Last good capture per window. Fullscreen apps live on their own Space
    /// and cannot be captured from another one (SCStream fails with -3811), so
    /// a picture taken while the window *was* reachable is the only thing we
    /// can show for them.
    ///
    /// Every entry is a real screenshot of someone's screen, so this is bounded
    /// on both axes: at most `cacheLimit` frames, and never outliving the ring
    /// that displayed them. Orbit sits in the menu bar all day; an unbounded
    /// cache would keep messages, mail and password managers in memory
    /// indefinitely, and grow without limit while doing it.
    private var cache: [CGWindowID: CGImage] = [:]
    private var cacheOrder: [CGWindowID] = []
    private static let cacheLimit = 12

    private init() {}

    private func remember(_ image: CGImage, for id: CGWindowID) {
        if cache.updateValue(image, forKey: id) == nil {
            cacheOrder.append(id)
        }
        while cacheOrder.count > Self.cacheLimit {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    /// Called when the ring goes away. Window contents have no reason to
    /// outlive the panel that showed them.
    func flushCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }

    // MARK: - Permission

    static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 窗口预览开着，屏幕录制权限却读不到。
    ///
    /// 这个组合只有一种解释：预览是这个人明确要的功能，而它此刻用不了。最常见的
    /// 起因是升级 —— Orbit 是 ad-hoc 签名的，每次构建 code hash 都会变，而 macOS
    /// 是按 hash 记授权的，于是「系统设置」里 Orbit 的条目还亮着、实际早已失效。
    ///
    /// 失效的后果偏偏是安静的：环照开，应用之间照切，只有窗口级切换悄悄退回到
    /// 普通激活 —— Chromium 系应用尤其明显，它们的窗口只能靠标题认，而标题在
    /// macOS 上算屏幕内容。所以这里必须主动说出来，等人自己发现是等不到的。
    ///
    /// 关掉预览的人不会看到任何提示：他没要这个功能，缺权限也就不是问题。
    static var windowPreviewNeedsAuthorization: Bool {
        OrbitPreferences.windowPreviewEnabled && !hasScreenRecordingPermission()
    }

    /// Prompts once. macOS only applies a freshly granted permission after the
    /// app restarts, so callers should say so rather than silently failing.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Activation

    /// Points an app at one specific window. There is no public API from
    /// CGWindowID to a window, so the window is found again through
    /// Accessibility — which Orbit already holds permission for.
    ///
    /// Call this *before* activating the app. macOS follows an application onto
    /// the Space its main window lives on, so naming the window first is what
    /// makes the switch land there; raising a window after the app is already
    /// frontmost only reorders windows on the Space you have already arrived at,
    /// which leaves every fullscreen window unreachable.
    ///
    /// - Returns: false when the app exposes no matching window, and the caller
    ///   should fall back to activating the application on its own.
    @discardableResult
    static func focus(_ target: WindowTarget, pid: pid_t) -> Bool {
        guard let window = axWindow(matching: target, pid: pid) else { return false }

        // A minimized window will not come forward for either call below.
        var minimized: AnyObject?
        if AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized) == .success,
           minimized as? Bool == true {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        }

        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)

        // The raise is the part that moves the user somewhere. If it failed,
        // reporting success would suppress the caller's fallback and leave the
        // wrong window in front. (kAXMain above is allowed to fail on its own:
        // some windows reject it yet still raise fine.)
        return AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success
    }

    /// Whether a successful Accessibility raise is enough to finish the
    /// requested switch.
    ///
    /// `kAXRaiseAction` can report success for a window on another Space while
    /// leaving that Space unchanged. This matters when the target belongs to
    /// the app the user is already in: activating the same process afterward
    /// does not make macOS follow a newly selected app, so the old fullscreen
    /// Space remains visible. In that one case the caller must continue to the
    /// app's Window-menu path, whose action really does cross Spaces.
    ///
    /// A target already on-screen can be raised normally. A target in another
    /// process can still use direct focus because the process activation that
    /// follows makes macOS travel to the focused window's Space.
    nonisolated static func directFocusCanCompleteSwitch(
        focusSucceeded: Bool,
        targetWasOnScreen: Bool,
        targetProcess: pid_t,
        originatingFrontmostProcess: pid_t?
    ) -> Bool {
        guard focusSucceeded else { return false }
        return targetWasOnScreen || targetProcess != originatingFrontmostProcess
    }

    /// The app's window that best answers to `target`.
    ///
    /// 三级判据，能问到窗口号就不必猜。
    ///
    /// `_AXUIElementGetWindow` hands back the very `CGWindowID` the window was
    /// listed under, which settles the question outright. It is also the fix for
    /// a real misfire: titles do not survive the trip between frameworks intact
    /// — Chrome hands ScreenCaptureKit `PV UV 数据处理` and Accessibility
    /// `PV UV 数据处理 - Google Chrome - YC (AI Profile)` for the same window —
    /// so when the title misses, the frame used to decide. Several fullscreen
    /// Chrome windows report *identical* frames, so that fallback would raise
    /// whichever one AX happened to list first and then report success, which
    /// suppressed the Window-menu path that could actually have crossed Spaces.
    ///
    /// 所以窗口号一旦全员可问，它就是唯一的判据：问遍了都没有这一号，说明辅助
    /// 功能确实看不见这扇窗，该老实返回 nil 去走下一级，而不是拿标题和尺寸凑一个
    /// 出来。只有在窗口号答不上来时（旧系统、或应用不给），才退回原来的标题/尺寸。
    private static func axWindow(matching target: WindowTarget, pid: pid_t) -> AXUIElement? {
        let axApp = AXUIElementCreateApplication(pid)
        // An app busy on its main thread answers slowly or not at all, and the
        // app switch is waiting on this call. Give up rather than stall.
        AXUIElementSetMessagingTimeout(axApp, 0.4)

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], !windows.isEmpty else { return nil }

        var titleOnly: AXUIElement?
        var frameOnly: AXUIElement?
        var everyWindowNamedItsID = true

        for window in windows {
            if let id = axWindowID(of: window) {
                if id == target.id { return window }
            } else {
                everyWindowNamedItsID = false
            }

            let titleAgrees = titles(axTitle(of: window), agreeWith: target.title)
            let frameAgrees = frame(of: window).map { $0.matches(target.frame) } == true

            if titleAgrees, frameAgrees { return window }
            if titleAgrees, titleOnly == nil { titleOnly = window }
            if frameAgrees, frameOnly == nil { frameOnly = window }
        }

        // 每扇窗都报得出窗口号，而没有一个是目标：这是一个确定的「没有」。
        guard !everyWindowNamedItsID else { return nil }

        // Title before frame: windows people keep several of are usually the
        // same size as each other, so a frame is the weaker discriminator.
        return titleOnly ?? frameOnly
    }

    /// 这个 AX 窗口在窗口服务那边的号码。
    ///
    /// `_AXUIElementGetWindow` is the one bridge between Accessibility and the
    /// window server, and it has no public equivalent — the same reason AltTab,
    /// Rectangle and yabai all reach for it. It is resolved at run time instead
    /// of being linked against, so a system that no longer exports it costs the
    /// precise match and nothing else: every caller already handles `nil`.
    private static func axWindowID(of window: AXUIElement) -> CGWindowID? {
        guard let getWindow = axWindowIDFunction else { return nil }
        var id: CGWindowID = 0
        guard getWindow(window, &id) == .success, id != kCGNullWindowID else { return nil }
        return id
    }

    private typealias AXWindowIDFunction = @convention(c) (
        AXUIElement,
        UnsafeMutablePointer<CGWindowID>
    ) -> AXError

    /// 只解析一次。`dlsym` 每次调用都要走一遍符号表，而这个函数在一次切换里会被
    /// 问上十几遍。
    private static let axWindowIDFunction: AXWindowIDFunction? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else {
            return nil
        }
        return unsafeBitCast(symbol, to: AXWindowIDFunction.self)
    }()

    /// Internal for the unit tests; pure, so `nonisolated` is safe.
    nonisolated static func titles(_ axTitle: String?, agreeWith captured: String) -> Bool {
        guard let axTitle, !axTitle.isEmpty, !captured.isEmpty else { return false }
        return axTitle == captured || axTitle.hasPrefix(captured) || captured.hasPrefix(axTitle)
    }

    private static func axTitle(of window: AXUIElement) -> String? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = axValue(kAXPositionAttribute, of: window, .cgPoint, CGPoint.zero),
              let size = axValue(kAXSizeAttribute, of: window, .cgSize, CGSize.zero) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// `AXValue` unwrapping needs somewhere typed to write into, which is what
    /// `empty` is for — its only job is to carry the type.
    private static func axValue<T>(
        _ attribute: String,
        of window: AXUIElement,
        _ type: AXValueType,
        _ empty: T
    ) -> T? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(window, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }

        var result = empty
        let unwrapped = withUnsafeMutablePointer(to: &result) {
            // Safe: the type ID was just checked.
            AXValueGetValue(value as! AXValue, type, $0)
        }
        return unwrapped ? result : nil
    }

    // MARK: - Capture

    /// Thumbnails for the windows belonging to `processIdentifier`, largest
    /// first, and never more than the carousel can show.
    ///
    /// Deliberately asks for off-screen windows too: `isOnScreen` is false for
    /// anything the user has covered with another window, so filtering on it
    /// hides most apps. ScreenCaptureKit still renders those windows.
    ///
    /// What separates a real window from the pile of helper surfaces every app
    /// keeps around is the pair (`windowLayer == 0`, non-empty title) — menu
    /// bar shadows, autofill panels and placeholder windows all come back
    /// untitled or on a higher layer.
    /// - Parameter scale: 目标屏的像素密度，由调用方给出 —— 这个服务不该假设
    ///   圆环出现在主屏上。
    /// - Parameter hiding: 要略过的窗口，通常是用户此刻正看着的那一扇。
    /// - Parameter preferredWindowIDs: 该应用的窗口 MRU；命中的窗口先于面积排序，
    ///   让转盘默认目标和快速松手目标保持一致。
    /// - Parameter onPartial: 每截好一扇窗就带着当前这份结果调用一次。
    ///
    ///   截图是逐扇顺序做的，而以前只有整轮跑完才交出结果——于是队列里但凡有一扇
    ///   要走 `SCStream` 的全屏窗（单扇最多两秒），前面五张早就截好的图也一起被扣
    ///   着，面板空着，松手时也就没有窗口目标可用。谁先截好谁先算数，把那段窗口期
    ///   压到第一扇窗的耗时。
    func previews(
        forProcessIdentifier pid: pid_t,
        scale: CGFloat,
        hiding hidden: CGWindowID? = nil,
        preferredWindowIDs: [CGWindowID] = [],
        onPartial: (([WindowPreview]) -> Void)? = nil
    ) async -> [WindowPreview] {
        guard Self.hasScreenRecordingPermission() else { return [] }

        let windows: [SCWindow]
        do {
            let preferredRank = Dictionary(
                uniqueKeysWithValues: preferredWindowIDs.enumerated().map { ($0.element, $0.offset) }
            )
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            windows = content.windows
                .filter { $0.owningApplication?.processID == pid }
                .filter { $0.windowID != hidden }
                .filter { $0.windowLayer == 0 }
                .filter { !($0.title ?? "").isEmpty }
                .filter {
                    $0.frame.width >= OrbitPreferences.minimumRealWindowSize.width
                        && $0.frame.height >= OrbitPreferences.minimumRealWindowSize.height
                }
                .sorted { lhs, rhs in
                    switch (preferredRank[lhs.windowID], preferredRank[rhs.windowID]) {
                    case let (left?, right?) where left != right:
                        return left < right
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    default:
                        break
                    }
                    // Whatever the user is actually looking at goes first.
                    if lhs.isOnScreen != rhs.isOnScreen { return lhs.isOnScreen }
                    return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
                }
        } catch {
            return []
        }

        // Any window that gets captured can be brought to the front of the
        // carousel, so each is captured at the size of that front slot.
        let captureWidth = OrbitPreferences.previewCaptureWidth(scale: scale)

        // 只截转盘放得下的那几个窗口。
        //
        // Every window used to be captured, and the caller then kept the first
        // `maxVisiblePreviews`. A browser with twenty windows open paid twenty
        // stream captures for six pictures — and paid for them inside the pause
        // between summoning the ring and the panel filling in.
        //
        // 计数数的是"截出内容的窗口"而不是"截过的窗口"：空白的辅助窗口在下面会
        // 被丢掉，把它们算进席位会让面板少几张图。
        var previews: [WindowPreview] = []
        var windowsWithContent = 0

        for window in windows {
            if Task.isCancelled { return previews }
            guard windowsWithContent < OrbitPreferences.maxVisiblePreviews,
                  previews.count < OrbitPreferences.maxPreviewCaptures else { break }

            let fresh = await Self.capture(window, width: captureWidth, scale: scale)
            if let fresh {
                remember(fresh, for: window.windowID)
            }
            let image = fresh ?? cache[window.windowID]

            // Measure the captured image, not the window: a stream can hand
            // back a slightly different size than requested, and a frame that
            // disagrees with its border is exactly what shows up as a
            // misaligned highlight.
            let ratio: CGFloat = if let image, image.height > 0 {
                CGFloat(image.width) / CGFloat(image.height)
            } else if window.frame.height > 0 {
                window.frame.width / window.frame.height
            } else {
                1
            }

            // 逐像素扫一遍整张图，不能占着主线程 —— 事件 tap 的回调也在这条线上，
            // 主线程停一拍，全系统的键盘输入就跟着停一拍。
            let variance: Double = if let image {
                await Task.detached(priority: .userInitiated) {
                    Self.contentVariance(image)
                }.value
            } else {
                .greatestFiniteMagnitude
            }

            previews.append(
                WindowPreview(
                    id: window.windowID,
                    title: window.title ?? "",
                    frame: window.frame,
                    image: image,
                    aspectRatio: ratio,
                    scale: scale,
                    contentVariance: variance,
                    isStale: fresh == nil && image != nil
                )
            )

            if variance >= Self.blankVarianceThreshold {
                windowsWithContent += 1
            }

            // 交出的每一份中间结果都过同一道空白过滤，面板和松手目标才不会先看到
            // 一扇随后就会被丢掉的辅助窗。
            onPartial?(Self.droppingBlankWindows(previews))
        }

        return Self.droppingBlankWindows(previews)
    }

    /// Apps keep windows that are titled and normal-layered but render as a
    /// flat rectangle — WeChat's 280x380 helper is one. They are only
    /// distinguishable by their contents, so drop them when the app has a real
    /// window to show instead. An app whose only window looks flat still gets
    /// shown; better a dull preview than none.
    private static func droppingBlankWindows(_ previews: [WindowPreview]) -> [WindowPreview] {
        guard previews.count > 1 else { return previews }
        let withContent = previews.filter { $0.contentVariance >= blankVarianceThreshold }
        return withContent.isEmpty ? previews : withContent
    }

    private static let blankVarianceThreshold: Double = 12

    /// A window's reported frame can be wider than what it actually draws — a
    /// fullscreen Chrome window reports 1512x827 but only fills 1.595 of that
    /// ratio, handing back the remaining 13% as transparent columns. Any border
    /// drawn around such an image sits well clear of the picture, so trim the
    /// frame down to the pixels that carry content.
    nonisolated private static func trimmingTransparentEdges(_ image: CGImage) -> CGImage {
        guard image.bitsPerPixel == 32,
              let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else { return image }

        // Without an alpha channel there are no transparent edges to trim.
        let alphaFirst: Bool
        switch image.alphaInfo {
        case .first, .premultipliedFirst: alphaFirst = true
        case .last, .premultipliedLast: alphaFirst = false
        default: return image
        }

        let bytesPerPixel = 4
        let bytesPerRow = image.bytesPerRow
        // A little-endian buffer stores the components back to front, so an
        // "alpha first" format actually keeps alpha in the last byte. BGRA
        // frames out of SCStream land exactly there.
        let isLittleEndian = image.bitmapInfo.contains(.byteOrder32Little)
        let alphaOffset = (alphaFirst == isLittleEndian) ? bytesPerPixel - 1 : 0
        /// Anti-aliased window corners fade out rather than cut off.
        let opaqueEnough: UInt8 = 8

        var minX = image.width
        var minY = image.height
        var maxX = -1
        var maxY = -1

        for y in 0 ..< image.height {
            let row = y * bytesPerRow
            for x in 0 ..< image.width where bytes[row + x * bytesPerPixel + alphaOffset] > opaqueEnough {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }

        guard maxX >= minX, maxY >= minY else { return image }
        let width = maxX - minX + 1
        let height = maxY - minY + 1
        guard width < image.width || height < image.height else { return image }

        return image.cropping(
            to: CGRect(x: minX, y: minY, width: width, height: height)
        ) ?? image
    }

    /// Standard deviation of luminance over a sparse sample. Near zero means a
    /// flat, contentless window.
    nonisolated private static func contentVariance(_ image: CGImage) -> Double {
        guard let data = image.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data),
              image.bitsPerPixel >= 24 else { return .greatestFiniteMagnitude }

        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0.0

        for y in stride(from: 0, to: image.height, by: 4) {
            for x in stride(from: 0, to: image.width, by: 4) {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let luminance = Double(bytes[offset]) * 0.3
                    + Double(bytes[offset + 1]) * 0.59
                    + Double(bytes[offset + 2]) * 0.11
                sum += luminance
                sumOfSquares += luminance * luminance
                count += 1
            }
        }

        guard count > 0 else { return .greatestFiniteMagnitude }
        let mean = sum / count
        return max(0, sumOfSquares / count - mean * mean).squareRoot()
    }

    /// Two paths, because they do not have the same reach.
    ///
    /// `SCScreenshotManager` is the fast one (~18ms) but it cannot capture a
    /// window that lives on another Space — every fullscreen app does, and it
    /// fails there with SCStreamError -3811. `SCStream` on the identical
    /// filter *can* reach those windows, at the cost of spinning up a stream,
    /// so it is the fallback rather than the default.
    ///
    /// `nonisolated` on purpose: this runs off the main actor so that
    /// `trimmingTransparentEdges`, which walks every pixel of the captured frame,
    /// never lands on the thread the event tap's callback shares. `scale` is
    /// passed in because `NSScreen` may only be read from the main actor.
    nonisolated private static func capture(
        _ window: SCWindow,
        width: Int,
        scale: CGFloat
    ) async -> CGImage? {
        // Never upscale: a small window asked for at grid resolution just
        // costs more pixels without carrying more detail.
        let nativeWidth = Int((window.frame.width * scale).rounded())
        let targetWidth = max(1, min(width, nativeWidth))

        let ratio = window.frame.width > 0 ? window.frame.height / window.frame.width : 1
        let configuration = SCStreamConfiguration()
        configuration.width = targetWidth
        configuration.height = max(1, Int(CGFloat(targetWidth) * ratio))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.captureResolution = .best

        let filter = SCContentFilter(desktopIndependentWindow: window)

        if let image = try? await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        ) {
            return Self.trimmingTransparentEdges(image)
        }

        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 10)
        let streamed = await SingleFrameStreamCapture()
            .image(filter: filter, configuration: configuration)
        return streamed.map(Self.trimmingTransparentEdges)
    }
}

extension CGRect {
    /// Same window, allowing for the rounding that separates what
    /// ScreenCaptureKit reports from what Accessibility reports.
    /// Internal for the unit tests.
    func matches(_ other: CGRect) -> Bool {
        let tolerance: CGFloat = 2
        return abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

/// Pulls exactly one frame out of an `SCStream` and tears it down. This is the
/// only way to reach windows on other Spaces.
private final class SingleFrameStreamCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<CGImage?, Never>?
    nonisolated(unsafe) private var stream: SCStream?
    nonisolated(unsafe) private var hasFinished = false

    /// Streams that never deliver a frame must not hang the preview panel.
    private static let timeout: TimeInterval = 2

    /// 取消时立刻收工，不把两秒的超时耗满。
    ///
    /// The preview panel re-runs this whenever the selection moves, so a sweep
    /// across the ring cancels one capture after another. Without a cancellation
    /// handler each abandoned stream still held its slot for the full timeout, and
    /// because windows are captured one after another those timeouts stacked up —
    /// a couple of fullscreen apps was enough to freeze the panel for seconds.
    func image(filter: SCContentFilter, configuration: SCStreamConfiguration) async -> CGImage? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                guard !hasFinished else {
                    lock.unlock()
                    continuation.resume(returning: nil)
                    return
                }
                self.continuation = continuation
                lock.unlock()

                let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)

                do {
                    try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))

                    // Cancellation can win while the stream is being created or
                    // while its output is being registered. Do not start a
                    // stream whose continuation has already been resumed.
                    lock.lock()
                    guard !hasFinished else {
                        lock.unlock()
                        return
                    }
                    self.stream = stream
                    lock.unlock()

                    stream.startCapture { [weak self] error in
                        if error != nil { self?.finish(with: nil) }
                    }

                    // A cancellation may arrive between the guarded setup and
                    // startCapture. The post-start check closes that remaining
                    // window instead of leaving an orphaned stream alive.
                    lock.lock()
                    let cancelledDuringStart = hasFinished
                    lock.unlock()
                    if cancelledDuringStart {
                        stream.stopCapture { _ in }
                    }
                } catch {
                    finish(with: nil)
                    return
                }

                DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                    self?.finish(with: nil)
                }
            }
        } onCancel: {
            finish(with: nil)
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { finish(with: image) }
    }

    nonisolated private func finish(with image: CGImage?) {
        lock.lock()
        guard !hasFinished else {
            lock.unlock()
            return
        }
        hasFinished = true
        let continuation = self.continuation
        let stream = self.stream
        self.continuation = nil
        self.stream = nil
        lock.unlock()

        if let stream {
            stream.stopCapture { _ in }
        }
        continuation?.resume(returning: image)
    }
}
