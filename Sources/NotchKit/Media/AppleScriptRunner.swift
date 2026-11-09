import AppKit
import Foundation

public enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "com.notch.applescript", qos: .userInitiated)
    nonisolated(unsafe) private static var scriptCache: [String: NSAppleScript] = [:]
    private static let maxCacheSize = 20

    private static func cachedOrNewScript(_ source: String) -> NSAppleScript? {
        if let cached = scriptCache[source] {
            return cached
        }
        guard let script = NSAppleScript(source: source) else { return nil }
        script.compileAndReturnError(nil)
        if scriptCache.count >= maxCacheSize {
            scriptCache.removeAll(keepingCapacity: true)
        }
        scriptCache[source] = script
        return script
    }

    @discardableResult
    public static func runSync(_ source: String) -> String? {
        queue.sync {
            var error: NSDictionary?
            guard let script = cachedOrNewScript(source) else { return nil }
            let result = script.executeAndReturnError(&error)
            return error == nil ? result.stringValue : nil
        }
    }

    public static func runAsync(_ source: String) {
        queue.async {
            var error: NSDictionary?
            guard let script = cachedOrNewScript(source) else { return }
            script.executeAndReturnError(&error)
        }
    }
}
