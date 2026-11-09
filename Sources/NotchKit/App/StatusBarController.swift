import AppKit
import Combine
import Carbon

@MainActor
public final class StatusBarController {
    public private(set) var statusItem: NSStatusItem?
    private let viewModel: NotchViewModel
    private weak var windowController: NotchWindowController?
    private var cancellables = Set<AnyCancellable>()

    public init(viewModel: NotchViewModel, windowController: NotchWindowController) {
        self.viewModel = viewModel
        self.windowController = windowController
        setupStatusItem()
        bindViewModel()
        setupHotKeys()
    }

    private func setupHotKeys() {
        // Global Hotkeys:
        // Use chorded shortcuts (⌃⌘) so universal macOS shortcuts (⌘L for browser URL bar, ⌘P for print)
        // are not intercepted system-wide. Local ⌘L and ⌘P remain handled when the NotchPanel is focused.

        // 1. Toggle Lyrics: ⌃⌘L (kVK_ANSI_L, cmdKey | controlKey)
        HotKeyManager.shared.register(keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            self?.toggleLyrics()
        }

        // 2. Toggle Pin: ⌃⌘P (kVK_ANSI_P, cmdKey | controlKey)
        HotKeyManager.shared.register(keyCode: UInt32(kVK_ANSI_P), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            self?.togglePin()
        }

        // 3. Toggle Overlay: ⌃⌘N (kVK_ANSI_N, cmdKey | controlKey)
        HotKeyManager.shared.register(keyCode: UInt32(kVK_ANSI_N), modifiers: UInt32(cmdKey | controlKey)) { [weak self] in
            self?.toggleOverlay()
        }
    }

    private func bindViewModel() {
        viewModel.$isPinned
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)

        viewModel.$showLyrics
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshMenu() }
            .store(in: &cancellables)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = menuBarIcon()
        }

        let menu = NSMenu()

        let titleItem = NSMenuItem(title: "Notch Music", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let toggleItem = NSMenuItem(title: "Toggle Notch Overlay", action: #selector(toggleOverlay), keyEquivalent: "n")
        toggleItem.keyEquivalentModifierMask = [.command, .control]
        toggleItem.target = self
        menu.addItem(toggleItem)

        let pinItem = NSMenuItem(title: "Keep Expanded (Pin)", action: #selector(togglePin), keyEquivalent: "p")
        pinItem.keyEquivalentModifierMask = [.command, .control]
        pinItem.target = self
        pinItem.state = viewModel.isPinned ? .on : .off
        menu.addItem(pinItem)

        let lyricsItem = NSMenuItem(title: "Show Lyrics", action: #selector(toggleLyrics), keyEquivalent: "l")
        lyricsItem.keyEquivalentModifierMask = [.command, .control]
        lyricsItem.target = self
        lyricsItem.state = viewModel.showLyrics ? .on : .off
        menu.addItem(lyricsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Notch", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        self.statusItem = item
    }

    private func menuBarIcon() -> NSImage {
        let image: NSImage
        if let icon = Bundle.main.image(forResource: "AppIcon") ?? NSImage(named: "AppIcon") {
            image = icon.copy() as! NSImage
        } else if let path = ["Resources/AppIcon.icns", "Resources/AppIcon.png", "../Resources/AppIcon.icns"].first(where: { FileManager.default.fileExists(atPath: $0) }),
                  let icon = NSImage(contentsOfFile: path) {
            image = icon.copy() as! NSImage
        } else if let icon = NSApp.applicationIconImage {
            image = icon.copy() as! NSImage
        } else {
            image = NSImage(systemSymbolName: "music.note.house.fill", accessibilityDescription: "Notch Music") ?? NSImage()
            image.isTemplate = true
            return image
        }
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Notch Music"
        return image
    }

    @objc private func toggleOverlay() {
        windowController?.toggleVisibility()
    }

    @objc private func togglePin() {
        viewModel.togglePin()
        refreshMenu()
    }

    @objc private func toggleLyrics() {
        viewModel.toggleLyrics()
        refreshMenu()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    public func refreshMenu() {
        guard let menu = statusItem?.menu else { return }
        for item in menu.items {
            if item.action == #selector(togglePin) {
                item.state = viewModel.isPinned ? .on : .off
            } else if item.action == #selector(toggleLyrics) {
                item.state = viewModel.showLyrics ? .on : .off
            }
        }
    }
}
