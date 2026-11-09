import AppKit

public final class NotchPanel: NSPanel {
    public init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = .screenSaver
        self.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]
        self.isMovable = false
        self.isMovableByWindowBackground = false
        self.hidesOnDeactivate = false
    }

    public var onEscape: (() -> Void)?
    public var onToggleLyrics: (() -> Void)?
    public var onTogglePin: (() -> Void)?
    public var onPlayPause: (() -> Void)?

    public override var canBecomeKey: Bool {
        true
    }

    public override var canBecomeMain: Bool {
        false
    }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onEscape?()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased()

        // ⌘L or ⌃⌘L: Toggle lyrics
        if (flags == .command || flags == [.command, .control]) && (chars == "l" || event.keyCode == 37) {
            onToggleLyrics?()
            return
        }

        // ⌘P or ⌃⌘P: Toggle pin
        if (flags == .command || flags == [.command, .control]) && (chars == "p" || event.keyCode == 35) {
            onTogglePin?()
            return
        }

        // Spacebar: Play / Pause toggle when panel is focused
        if flags.isEmpty && event.keyCode == 49 {
            onPlayPause?()
            return
        }

        super.keyDown(with: event)
    }
}
