//
//  WelcomeWindowController.swift
//  Orbit
//

import AppKit
import SwiftUI

final class WelcomeWindowController: NSWindowController {
    static let shared = WelcomeWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("onboarding.title", comment: "Welcome window title")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)

        window.contentView = NSHostingView(
            rootView: WelcomeView {
                window.performClose(nil)
            }
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct WelcomeView: View {
    let onStart: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "circle.hexagongrid.circle")
                .font(.system(size: 74, weight: .medium))
                .foregroundStyle(.primary)

            VStack(spacing: 8) {
                Text("onboarding.title")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("onboarding.description")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button("onboarding.start") {
                UserDefaults.standard.set(true, forKey: "hasSeenWelcome")
                onStart()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(36)
    }
}
