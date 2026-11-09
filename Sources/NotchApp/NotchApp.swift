import AppKit
import Foundation
import NotchKit

@main
final class NotchApp: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var statusBarController: StatusBarController?

    static func main() {
        let app = NSApplication.shared
        let delegate = NotchApp()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Run as background accessory application (no Dock icon, status bar & notch overlay only)
        NSApp.setActivationPolicy(.accessory)

        let viewModel = NotchViewModel()
        let winController = NotchWindowController(viewModel: viewModel)
        self.windowController = winController

        let statusController = StatusBarController(viewModel: viewModel, windowController: winController)
        self.statusBarController = statusController

        print("Notch Music Prototype launched.")
        print("Screen: \(viewModel.screenManager.currentGeometry.screenFrame)")
        print("Hardware Notch: \(viewModel.screenManager.currentGeometry.hasPhysicalNotch)")
        print("Notch Rect: \(viewModel.screenManager.currentGeometry.notchRect)")
    }
}
