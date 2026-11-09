import AppKit
import Foundation

/// Represents the geometric layout and positioning of the notch.
public struct NotchGeometry: Equatable, Sendable {
    public let screenFrame: NSRect
    public let hasPhysicalNotch: Bool
    public let notchRect: NSRect
    public let wingWidth: CGFloat
    public let compactSize: CGSize
    public let expandedSize: CGSize

    public init(
        screenFrame: NSRect,
        hasPhysicalNotch: Bool,
        notchRect: NSRect,
        wingWidth: CGFloat = 72.0,
        expandedWidth: CGFloat = 520.0,
        expandedHeight: CGFloat = 290.0
    ) {
        self.screenFrame = screenFrame
        self.hasPhysicalNotch = hasPhysicalNotch
        self.notchRect = notchRect
        self.wingWidth = wingWidth
        self.compactSize = CGSize(
            width: notchRect.width + (wingWidth * 2.0),
            height: max(notchRect.height, 38.0)
        )
        self.expandedSize = CGSize(
            width: expandedWidth,
            height: expandedHeight
        )
    }

    /// Computes window frame in screen coordinates for compact mode.
    public var compactFrame: NSRect {
        let x = notchRect.midX - (compactSize.width / 2.0)
        let y = screenFrame.maxY - compactSize.height
        return NSRect(x: x, y: y, width: compactSize.width, height: compactSize.height)
    }

    /// Computes window frame in screen coordinates for expanded mode.
    public var expandedFrame: NSRect {
        let x = notchRect.midX - (expandedSize.width / 2.0)
        let y = screenFrame.maxY - expandedSize.height
        return NSRect(x: x, y: y, width: expandedSize.width, height: expandedSize.height)
    }

    /// Rect for a combined bounding window that can host both compact and expanded layouts smoothly.
    public var maxWindowFrame: NSRect {
        let width = max(compactSize.width, expandedSize.width)
        let height = max(compactSize.height, expandedSize.height)
        let x = notchRect.midX - (width / 2.0)
        let y = screenFrame.maxY - height
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

/// Manages notch detection, multi-display handling, and screen changes.
@MainActor
public final class ScreenNotchManager: ObservableObject {
    @Published public private(set) var currentGeometry: NotchGeometry

    public static let shared = ScreenNotchManager()
    private var screenObserverToken: NSObjectProtocol?

    public init() {
        self.currentGeometry = ScreenNotchManager.calculateGeometry()
        registerScreenNotifications()
    }

    isolated deinit {
        if let screenObserverToken {
            NotificationCenter.default.removeObserver(screenObserverToken)
        }
    }

    private func registerScreenNotifications() {
        screenObserverToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateGeometry()
            }
        }
    }

    public func updateGeometry() {
        self.currentGeometry = ScreenNotchManager.calculateGeometry()
    }

    /// Determines the geometry for the best screen (prioritizing screen with notch).
    public static func calculateGeometry() -> NotchGeometry {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            let defaultFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
            let defaultNotch = NSRect(x: 615, y: 866, width: 210, height: 34)
            return NotchGeometry(
                screenFrame: defaultFrame,
                hasPhysicalNotch: false,
                notchRect: defaultNotch
            )
        }

        let targetScreen = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens[0]
        let hasPhysical = targetScreen.safeAreaInsets.top > 0

        if hasPhysical,
           let leftArea = targetScreen.auxiliaryTopLeftArea,
           let rightArea = targetScreen.auxiliaryTopRightArea {
            let notchLeft = leftArea.maxX
            let notchRight = rightArea.minX
            let width = max(notchRight - notchLeft, 160.0)
            let height = targetScreen.safeAreaInsets.top
            let y = targetScreen.frame.maxY - height
            let notchRect = NSRect(x: notchLeft, y: y, width: width, height: height)

            return NotchGeometry(
                screenFrame: targetScreen.frame,
                hasPhysicalNotch: true,
                notchRect: notchRect
            )
        } else {
            // Fallback centered at the top of the target screen
            let width: CGFloat = 208.0
            let height: CGFloat = 34.0
            let x = targetScreen.frame.midX - (width / 2.0)
            let y = targetScreen.frame.maxY - height
            let notchRect = NSRect(x: x, y: y, width: width, height: height)

            return NotchGeometry(
                screenFrame: targetScreen.frame,
                hasPhysicalNotch: false,
                notchRect: notchRect
            )
        }
    }
}
