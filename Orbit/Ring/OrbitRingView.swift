//
//  OrbitRingView.swift
//  Orbit
//
//  The ring itself: backdrop, trail, cards and hub, laid out by the model.
//

import AppKit
import SwiftUI

struct OrbitRingView: View {
    @ObservedObject var model: OrbitRingViewModel

    @State private var hasAppeared = false

    var body: some View {
        layout
            .frame(width: model.panelSize.width, height: model.panelSize.height)
            .onAppear { hasAppeared = true }
    }

    /// 1 表示扇面已经完全展开，0 表示所有卡片都还叠在中心。
    ///
    /// The whole panel used to arrive as one 0.9→1 scale, which is the motion a
    /// dialog makes: it says "a thing appeared", not "these came from
    /// somewhere". Deploying each card outward from the hub instead makes the
    /// ring's own geometry the animation — the cards travel the radius they
    /// live on — and gives the dismissal a path to mirror.
    private var deployProgress: Double {
        model.isDeployed(hasAppeared: hasAppeared) ? 1 : 0
    }

    /// 每张卡片错开一点起飞，扇面就是"甩"开的而不是"张"开的。
    ///
    /// Only on the way out. Staggering the collapse as well would leave the last
    /// card still travelling after the window is due to go, and a cancel has to
    /// feel immediate.
    private func deployDelay(for index: Int) -> Double {
        model.opensInstantly || model.isCollapsing ? 0 : Double(index) * 0.028
    }

    /// Two equal halves rather than an HStack sized by its contents. The ring
    /// canvas and the preview are very different widths, and letting either one
    /// absorb the leftover space is what pulled the pair off the screen's
    /// centre line; giving each the same half puts them on opposite ends of it.
    @ViewBuilder
    private var layout: some View {
        if model.showsPreview {
            HStack(spacing: 0) {
                ringCanvas
                    .frame(width: model.columnWidth)

                OrbitPreviewPanel(model: model)
                    .frame(width: model.columnWidth)
                    .opacity(deployProgress)
                    .animation(
                        model.deployAnimation(.easeOut(duration: 0.2).delay(model.isCollapsing ? 0 : 0.06)),
                        value: deployProgress
                    )
            }
        } else {
            ringCanvas
        }
    }

    private var ringCanvas: some View {
        let hub = CGPoint(x: model.canvasSize / 2, y: model.canvasSize / 2)

        return ZStack {
            if model.showsBackdrop {
                OrbitRingBackdrop(
                    radius: model.ringRadius,
                    thickness: OrbitPreferences.ringTrackThickness,
                    arc: model.backdropArc,
                    tint: OrbitPalette.backdropOnDusk
                )
                .position(hub)
                .opacity(deployProgress)
                .animation(
                    model.deployAnimation(.easeOut(duration: 0.28)),
                    value: deployProgress
                )
                .zIndex(-2)
            }

            // 虚线是笔，不是气氛，所以它跟 accent 走 —— Welcome 那条轨道用的
            // 也是 accent。跟着 backdrop 开关一起收：把柔光关掉的人要的是光秃
            // 的扇面，不是换一件新装饰。
            //
            // 用 `accentOnDusk` 而不是 `accent(on:)`：这根线落在 scrim 上，而
            // scrim 两个主题下都是暖影，所以决定它多亮的是那块地，不是系统主题。
            if model.showsBackdrop {
                OrbitTrail(
                    radius: model.orbitTrailRadius,
                    arc: model.backdropArc,
                    stops: model.apps.indices.map { model.angle(for: $0) },
                    selectedStop: model.selectedIndex,
                    tint: OrbitPalette.accentOnDusk,
                    progress: deployProgress
                )
                .position(hub)
                .animation(
                    model.deployAnimation(.spring(response: 0.4, dampingFraction: 0.82)),
                    value: deployProgress
                )
                .zIndex(-1)
            }

            ForEach(Array(model.apps.enumerated()), id: \.element.id) { index, app in
                let basePosition = model.position(for: index)
                OrbitAppCard(
                    app: app,
                    cardNumber: index + 1,
                    depthIndex: index,
                    depthCount: model.apps.count,
                    angle: model.angle(for: index),
                    isSelected: model.selectedID == app.id,
                    isDragging: model.draggedAppID == app.id,
                    isVanishing: model.departingAppIDs.contains(app.id),
                    dragOffset: model.draggedAppID == app.id ? model.dragOffset : .zero,
                    onSelect: { model.select(app) },
                    onHoverSelect: { model.selectFromHover(app) },
                    onDragChanged: { offset in
                        if model.draggedAppID != app.id {
                            model.beginAppDrag(app)
                        }
                        let draggedCenter = CGPoint(
                            x: basePosition.x + offset.width,
                            y: basePosition.y + offset.height
                        )
                        let distance = hypot(draggedCenter.x - hub.x, draggedCenter.y - hub.y)
                        model.updateAppDrag(
                            app,
                            offset: offset,
                            overCenter: distance <= OrbitPreferences.centerQuitReach
                        )
                    },
                    onDragEnded: { model.finishAppDrag(app) }
                )
                // 卡片是从中心甩出去的，收的时候原路收回去。
                .position(deployed(basePosition, from: hub))
                .scaleEffect(0.55 + 0.45 * deployProgress)
                .opacity(deployProgress)
                .animation(
                    model.deployAnimation(.spring(response: 0.42, dampingFraction: 0.8)
                            .delay(deployDelay(for: index))),
                    value: deployProgress
                )
                // A lifted card must never slide underneath its neighbours.
                .zIndex(model.draggedAppID == app.id ? 2 : (model.selectedID == app.id ? 1 : 0))
            }

            OrbitCenterControl(
                mode: model.centerMode,
                selectionToken: model.selectedID,
                isFileTargeted: Binding(
                    get: { model.fileDropPhase.acceptsHover },
                    set: { model.setFileDragTargeted($0) }
                ),
                onCancel: { model.cancel() },
                onConfirm: { model.confirmFromHub() },
                onDrop: { providers in model.handleFileDrop(providers) }
            )
            .position(hub)
            // 星芯先亮起来，卡片才从它里面飞出去 —— 光源不能比被照亮的东西晚到。
            .scaleEffect(0.7 + 0.3 * deployProgress)
            .opacity(deployProgress)
            .animation(
                model.deployAnimation(.spring(response: 0.3, dampingFraction: 0.85)),
                value: deployProgress
            )
            .zIndex(3)
        }
        .frame(width: model.canvasSize, height: model.canvasSize)
        .background(Color.clear)
        // 画布按扇面的重心回正，而不是按它自己的几何中心。
        .offset(model.fanRecentring)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.selectedID)
        .animation(.spring(response: 0.26, dampingFraction: 0.8), value: model.centerMode)
    }

    /// 卡片在展开途中该待的位置：从中心一路走到它在环上的家。
    private func deployed(_ destination: CGPoint, from hub: CGPoint) -> CGPoint {
        let t = CGFloat(deployProgress)
        return CGPoint(
            x: hub.x + (destination.x - hub.x) * t,
            y: hub.y + (destination.y - hub.y) * t
        )
    }
}
