import Foundation

/// Represents a single synchronized lyric line with an active timestamp.
public struct LyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let timestamp: TimeInterval
    public let text: String

    public init(id: Int, timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }
}
