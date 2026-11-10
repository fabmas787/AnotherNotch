import AppKit
import Foundation

public enum AppleScriptRunner {
    private static let queueKey = DispatchSpecificKey<Void>()
    private static let queue: DispatchQueue = {
        let q = DispatchQueue(label: "com.notch.applescript", qos: .userInitiated)
        q.setSpecific(key: queueKey, value: ())
        return q
    }()
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

    private static func execute(_ source: String) -> String? {
        var error: NSDictionary?
        guard let script = cachedOrNewScript(source) else { return nil }
        let result = script.executeAndReturnError(&error)
        return error == nil ? result.stringValue : nil
    }

    private final class Box: @unchecked Sendable {
        var value: String?
        var finished = false
    }

    @discardableResult
    public static func runSync(_ source: String) -> String? {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return execute(source)
        }
        if Thread.isMainThread {
            let box = Box()
            queue.async {
                box.value = execute(source)
                box.finished = true
            }
            while !box.finished {
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
            return box.value
        }
        return queue.sync {
            execute(source)
        }
    }

    public static func runAsync(_ source: String) {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            _ = execute(source)
        } else {
            queue.async {
                _ = execute(source)
            }
        }
    }
}
