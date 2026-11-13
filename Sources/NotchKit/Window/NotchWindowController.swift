import AppKit
import SwiftUI
import Combine

public final class NotchPassthroughHostingView<Content: View>: NSHostingView<Content> {
    public var activeBoundsProvider: (() -> NSRect)?

    public override func hitTest(_ point: NSPoint) -> NSView? {
        if let active = activeBoundsProvider?() {
            // Tight interactive rect: expand only when cursor is directly on or very close to the notch
            let interactiveRect = active.insetBy(dx: 0, dy: -1)
            if !interactiveRect.contains(point) {
                return nil
            }
        }
        return super.hitTest(point)
    }
}

@MainActor
public final class NotchWindowController: ObservableObject {
    public let viewModel: NotchViewModel
    public private(set) var panel: NotchPanel?
    private var hostingView: NotchPassthroughHostingView<NotchRootView>?
    private var cancellables = Set<AnyCancellable>()

    public init(viewModel: NotchViewModel) {
        self.viewModel = viewModel
        setupWindow()
        bindViewModel()
    }

    private func setupWindow() {
        let maxFrame = viewModel.screenManager.currentGeometry.maxWindowFrame
        let newPanel = NotchPanel(contentRect: maxFrame)

        let rootView = NotchRootView(viewModel: viewModel)
        let hosting = NotchPassthroughHostingView(rootView: rootView)
        hosting.frame = NSRect(origin: .zero, size: maxFrame.size)
        hosting.autoresizingMask = [.width, .height]

        hosting.activeBoundsProvider = { [weak self] in
            guard let self = self else { return .zero }
            let isExpanded = self.viewModel.isExpanded
            let geometry = self.viewModel.screenManager.currentGeometry
            let bounds = self.hostingView?.bounds ?? NSRect(origin: .zero, size: geometry.maxWindowFrame.size)

            let activeWidth = isExpanded ? geometry.expandedSize.width : geometry.compactSize.width
            let activeHeight = isExpanded ? geometry.expandedSize.height : geometry.compactSize.height
            let activeX = (bounds.width - activeWidth) / 2.0
            let activeY = bounds.height - activeHeight

            return NSRect(x: activeX, y: activeY, width: activeWidth, height: activeHeight)
        }

        newPanel.contentView = hosting
        newPanel.onEscape = { [weak self] in
            self?.viewModel.collapse()
        }
        newPanel.onToggleLyrics = { [weak self] in
            self?.viewModel.toggleLyrics()
        }
        newPanel.onTogglePin = { [weak self] in
            self?.viewModel.togglePin()
        }
        newPanel.onPlayPause = { [weak self] in
            self?.viewModel.togglePlayPause()
        }
        self.panel = newPanel
        self.hostingView = hosting

        updateWindowPosition(animated: false)
        newPanel.orderFrontRegardless()
    }

    private func bindViewModel() {
        // Observe geometry changes (screen connected/disconnected/resolution changed)
        viewModel.screenManager.$currentGeometry
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.updateWindowPosition(animated: false)
            }
            .store(in: &cancellables)

        // Ensure notch stays frontmost across space and full-screen transitions and app activations
        let workspaceNC = NSWorkspace.shared.notificationCenter
        Publishers.Merge3(
            workspaceNC.publisher(for: NSWorkspace.activeSpaceDidChangeNotification),
            workspaceNC.publisher(for: NSWorkspace.didActivateApplicationNotification),
            workspaceNC.publisher(for: NSWorkspace.didDeactivateApplicationNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            guard let self = self else { return }
            self.panel?.orderFrontRegardless()
            self.viewModel.clearHoverSuppression()
        }
        .store(in: &cancellables)

        // Become key only when pinned to intercept Escape key, preventing hover from stealing focus from other apps
        viewModel.$isPinned
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isPinned in
                guard let self = self else { return }
                if isPinned {
                    self.panel?.makeKey()
                } else {
                    NSApp.deactivate()
                }
            }
            .store(in: &cancellables)
    }

    public func updateWindowPosition(animated: Bool) {
        guard let panel = panel else { return }
        let maxFrame = viewModel.screenManager.currentGeometry.maxWindowFrame

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(maxFrame, display: true)
            }
        } else {
            panel.setFrame(maxFrame, display: true)
        }
    }

    public func toggleVisibility() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            updateWindowPosition(animated: false)
            panel.orderFrontRegardless()
        }
    }

    public func show() {
        panel?.orderFrontRegardless()
    }

    public func hide() {
        panel?.orderOut(nil)
    }
}
