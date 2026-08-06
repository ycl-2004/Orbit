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

struct WindowPreview: Identifiable, Sendable {
    let id: CGWindowID
    let title: String
    /// Nil when the window could not be captured and nothing was cached —
    /// the panel then falls back to showing the title alone.
    let image: CGImage?
    let aspectRatio: CGFloat
    /// Luminance spread; near zero means the window rendered as a flat block.
    let contentVariance: Double
    /// True when the image came from cache because a fresh capture failed.
    let isStale: Bool
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

    /// Prompts once. macOS only applies a freshly granted permission after the
    /// app restarts, so callers should say so rather than silently failing.
    @discardableResult
    static func requestScreenRecordingPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    // MARK: - Activation

    /// Brings one specific window of an app to the front. There is no public
    /// API from CGWindowID to a window, so match on title via Accessibility —
    /// which Orbit already has permission for. Returns false when the app
    /// exposes no matching AX window, and the caller just activates the app.
    static func raise(windowTitled title: String, pid: pid_t) -> Bool {
        guard !title.isEmpty else { return false }

        let axApp = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return false }

        for window in windows {
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue) == .success,
                  let windowTitle = titleValue as? String,
                  windowTitle == title else { continue }

            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
            return true
        }
        return false
    }

    // MARK: - Capture

    /// Thumbnails for every window belonging to `processIdentifier`, largest
    /// first.
    ///
    /// Deliberately asks for off-screen windows too: `isOnScreen` is false for
    /// anything the user has covered with another window, so filtering on it
    /// hides most apps. ScreenCaptureKit still renders those windows.
    ///
    /// What separates a real window from the pile of helper surfaces every app
    /// keeps around is the pair (`windowLayer == 0`, non-empty title) — menu
    /// bar shadows, autofill panels and placeholder windows all come back
    /// untitled or on a higher layer.
    func previews(forProcessIdentifier pid: pid_t) async -> [WindowPreview] {
        guard Self.hasScreenRecordingPermission() else { return [] }

        let windows: [SCWindow]
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: false
            )
            windows = content.windows
                .filter { $0.owningApplication?.processID == pid }
                .filter { $0.windowLayer == 0 }
                .filter { !($0.title ?? "").isEmpty }
                .filter {
                    $0.frame.width >= OrbitConfig.minimumRealWindowSize.width
                        && $0.frame.height >= OrbitConfig.minimumRealWindowSize.height
                }
                .sorted { lhs, rhs in
                    // Whatever the user is actually looking at goes first.
                    if lhs.isOnScreen != rhs.isOnScreen { return lhs.isOnScreen }
                    return lhs.frame.width * lhs.frame.height > rhs.frame.width * rhs.frame.height
                }
        } catch {
            return []
        }

        // Any of these can be brought to the front of the carousel, so all of
        // them are captured for that slot.
        let captureWidth = OrbitConfig.previewCaptureWidth

        var previews: [WindowPreview] = []
        for window in windows {
            if Task.isCancelled { return previews }

            let fresh = await capture(window, width: captureWidth)
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

            previews.append(
                WindowPreview(
                    id: window.windowID,
                    title: window.title ?? "",
                    image: image,
                    aspectRatio: ratio,
                    contentVariance: image.map(Self.contentVariance) ?? .greatestFiniteMagnitude,
                    isStale: fresh == nil && image != nil
                )
            )
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
    private static func trimmingTransparentEdges(_ image: CGImage) -> CGImage {
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
    private static func contentVariance(_ image: CGImage) -> Double {
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
    private func capture(_ window: SCWindow, width: Int) async -> CGImage? {
        // Never upscale: a small window asked for at grid resolution just
        // costs more pixels without carrying more detail.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
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

/// Pulls exactly one frame out of an `SCStream` and tears it down. This is the
/// only way to reach windows on other Spaces.
private final class SingleFrameStreamCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var stream: SCStream?
    private var hasFinished = false

    /// Streams that never deliver a frame must not hang the preview panel.
    private static let timeout: TimeInterval = 2

    func image(filter: SCContentFilter, configuration: SCStreamConfiguration) async -> CGImage? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation

            let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
            self.stream = stream

            do {
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
                stream.startCapture { [weak self] error in
                    if error != nil { self?.finish(with: nil) }
                }
            } catch {
                finish(with: nil)
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + Self.timeout) { [weak self] in
                self?.finish(with: nil)
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        if let image { finish(with: image) }
    }

    private func finish(with image: CGImage?) {
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
