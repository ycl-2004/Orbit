//
//  OnboardingWindowController.swift
//  Orbit
//

import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {
    static let shared = OnboardingWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = NSLocalizedString("onboarding.title", comment: "Welcome window title")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
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

    /// 镜像 `OrbitPreferences.showWelcomeOnLaunch`，让复选框自己有状态可画。
    @State private var showOnLaunch = OrbitPreferences.showWelcomeOnLaunch

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            Circle()
                .fill(OrbitPalette.denim.opacity(0.13))
                .frame(width: 310, height: 310)
                .blur(radius: 1)
                .offset(x: 170, y: -190)

            Circle()
                .fill(OrbitPalette.coral.opacity(0.10))
                .frame(width: 250, height: 250)
                .blur(radius: 1)
                .offset(x: -190, y: 250)

            VStack(spacing: 0) {
                brandHeader
                    .padding(.top, 34)

                WelcomeOrbitIllustration()
                    .padding(.top, 22)

                Text("onboarding.description")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .padding(.top, 16)

                HStack(spacing: 8) {
                    WelcomeStep(number: "01", title: "onboarding.step.hold", icon: "option")
                    WelcomeStep(number: "02", title: "onboarding.step.choose", icon: "cursorarrow.rays")
                    WelcomeStep(number: "03", title: "onboarding.step.release", icon: "arrow.up.right")
                }
                .padding(.top, 24)

                HStack(spacing: 8) {
                    KeycapView(text: "⌥")
                    Text("onboarding.trigger.note")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 20)

                Button("onboarding.start") {
                    UserDefaults.standard.set(true, forKey: "onboardingCompleted")
                    onStart()
                }
                .buttonStyle(.borderedProminent)
                .tint(OrbitPalette.burgundy)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 20)

                // 关掉这一页的开关就放在这一页上 —— 被它烦到的人正好在这里，
                // 让他为此翻一趟设置是说不过去的。
                Toggle(isOn: $showOnLaunch) {
                    Text("onboarding.showOnLaunch")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: showOnLaunch) { _, newValue in
                    OrbitPreferences.showWelcomeOnLaunch = newValue
                }
                .padding(.top, 14)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
    }

    private var brandHeader: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 82, height: 82)
                .shadow(color: .black.opacity(0.16), radius: 16, y: 7)

            Text("onboarding.title")
                .font(.system(size: 31, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text("onboarding.kicker")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}

private struct WelcomeOrbitIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(.white.opacity(0.7), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.10), radius: 18, y: 8)

            Ellipse()
                .stroke(OrbitPalette.burgundy.opacity(0.72), style: StrokeStyle(lineWidth: 2, dash: [5, 4]))
                .frame(width: 250, height: 112)

            WelcomeOrbitNode(icon: "sparkles", color: OrbitPalette.coral)
                .offset(x: -105, y: -24)
            WelcomeOrbitNode(icon: "rectangle.3.group.fill", color: OrbitPalette.denim)
                .offset(x: 105, y: -24)
            WelcomeOrbitNode(icon: "terminal.fill", color: OrbitPalette.burgundy)
                .offset(x: -80, y: 38)
            WelcomeOrbitNode(icon: "doc.text.fill", color: Color(red: 0.68, green: 0.54, blue: 0.70))
                .offset(x: 80, y: 38)

            ZStack {
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay {
                        Circle()
                            .strokeBorder(OrbitPalette.burgundy.opacity(0.28), lineWidth: 1)
                    }

                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(11)
            }
            .frame(width: 72, height: 72)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .frame(width: 360, height: 180)
    }
}

private struct WelcomeOrbitNode: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.25), radius: 7, y: 3)
            }
    }
}

private struct WelcomeStep: View {
    let number: String
    let title: LocalizedStringKey
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OrbitPalette.burgundy)
                    .frame(width: 38, height: 38)
                    .background {
                        Circle()
                            .fill(OrbitPalette.ivory)
                            .overlay {
                                Circle()
                                    .strokeBorder(OrbitPalette.burgundy.opacity(0.18), lineWidth: 1)
                            }
                    }

                Text(number)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(3)
                    .background(.regularMaterial, in: Circle())
                    .offset(x: 5, y: -3)
            }

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct KeycapView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .foregroundStyle(.primary)
            .frame(width: 25, height: 22)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.quaternary, lineWidth: 1)
            }
    }
}
