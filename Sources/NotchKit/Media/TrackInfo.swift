import AppKit
import Foundation
import ImageIO

public enum MediaSource: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto"
    case appleMusic = "Apple Music"
    case spotify = "Spotify"
    case demo = "Demo Player"

    public var id: String { rawValue }

    public var systemIcon: String {
        switch self {
        case .auto: return "sparkles"
        case .appleMusic: return "music.note"
        case .spotify: return "antenna.radiowaves.left.and.right"
        case .demo: return "play.circle.fill"
        }
    }
}

public struct TrackInfo: Equatable, Identifiable, @unchecked Sendable {
    public let id: String
    public let title: String
    public let artist: String
    public let album: String
    public let duration: TimeInterval
    public let artworkGradientStartHex: String
    public let artworkGradientEndHex: String
    public let artworkData: Data?
    public let decodedImage: NSImage?
    public let artworkURL: URL?
    public let source: MediaSource

    public init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        artworkGradientStartHex: String = "#2D3035",
        artworkGradientEndHex: String = "#151619",
        artworkData: Data? = nil,
        decodedImage: NSImage? = nil,
        artworkURL: URL? = nil,
        source: MediaSource
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artworkGradientStartHex = artworkGradientStartHex
        self.artworkGradientEndHex = artworkGradientEndHex
        self.artworkData = artworkData
        self.decodedImage = decodedImage ?? artworkData.flatMap { Self.downsampledImage(from: $0) }
        self.artworkURL = artworkURL
        self.source = source
    }

    public static func downsampledImage(from data: Data, maxDimension: CGFloat = 160) -> NSImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return NSImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ]
        guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgThumb, size: NSSize(width: maxDimension / 2.0, height: maxDimension / 2.0))
    }

    public static func == (lhs: TrackInfo, rhs: TrackInfo) -> Bool {
        lhs.id == rhs.id &&
        lhs.title == rhs.title &&
        lhs.artist == rhs.artist &&
        lhs.album == rhs.album &&
        lhs.duration == rhs.duration &&
        lhs.artworkGradientStartHex == rhs.artworkGradientStartHex &&
        lhs.artworkGradientEndHex == rhs.artworkGradientEndHex &&
        lhs.artworkData == rhs.artworkData &&
        lhs.artworkURL == rhs.artworkURL &&
        lhs.source == rhs.source
    }

    public static let empty = idle

    public static let idle = TrackInfo(
        title: "No Music Playing",
        artist: "Ready to play",
        album: "Notch Music",
        duration: 0.0,
        artworkGradientStartHex: "#2D3035",
        artworkGradientEndHex: "#151619",
        artworkData: nil,
        artworkURL: nil,
        source: .auto
    )
}
