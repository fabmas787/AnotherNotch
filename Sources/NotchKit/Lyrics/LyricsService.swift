import Foundation
import Combine

/// Fetches, caches, and syncs timecoded lyrics from LRCLIB.
@MainActor
public final class LyricsService: ObservableObject {
    public static let shared = LyricsService()

    @Published public private(set) var currentLyrics: [LyricLine] = []
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var isInstrumental: Bool = false
    @Published public private(set) var hasNoLyrics: Bool = false
    @Published public private(set) var currentTrackKey: String = ""
    public private(set) var isMovingForward: Bool = true

    /// Anticipation lead time (in seconds) to transition lyrics slightly before the vocal begins.
    public static let anticipationLeadTime: TimeInterval = 0.35

    private var lastActiveIndex: Int = -1
    private let maxCacheSize = 50
    private var cacheOrder: [String] = []
    private var cache: [String: CachedLyricsResult] = [:]
    private var activeFetchTask: Task<Void, Never>?
    private let urlSession: URLSession

    private struct CachedLyricsResult {
        let lines: [LyricLine]
        let isInstrumental: Bool
        let hasNoLyrics: Bool
    }

    public var cacheCount: Int {
        cache.count
    }

    public func isCached(key: String) -> Bool {
        cache[key] != nil
    }

    public func setCachedLyricsForTesting(key: String, lines: [LyricLine] = [], isInstrumental: Bool = false, hasNoLyrics: Bool = false) {
        storeInCache(key: key, result: CachedLyricsResult(lines: lines, isInstrumental: isInstrumental, hasNoLyrics: hasNoLyrics))
    }

    private func storeInCache(key: String, result: CachedLyricsResult) {
        if cache[key] == nil {
            if cacheOrder.count >= maxCacheSize {
                let oldest = cacheOrder.removeFirst()
                cache.removeValue(forKey: oldest)
            }
            cacheOrder.append(key)
        }
        cache[key] = result
    }

    private struct LRCLIBResponse: Decodable {
        let id: Int?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    public init(session: URLSession = .shared) {
        self.urlSession = session
        preloadDemoLyrics()
    }

    /// Primary entry point to sync lyrics when the playing track changes.
    public func fetchLyrics(for track: TrackInfo?) {
        activeFetchTask?.cancel()
        activeFetchTask = nil

        guard let track = track,
              !track.title.isEmpty,
              track.title != "No Music Playing",
              !track.artist.isEmpty else {
            resetState()
            currentTrackKey = ""
            return
        }

        let cleanTitle = sanitize(track.title)
        let cleanArtist = sanitize(track.artist)
        let key = "\(cleanTitle.lowercased())__\(cleanArtist.lowercased())"

        guard key != currentTrackKey else { return }
        currentTrackKey = key

        // Check in-memory cache first
        if let cached = cache[key] {
            applyResult(cached)
            return
        }

        isLoading = true
        isInstrumental = false
        hasNoLyrics = false
        currentLyrics = []

        activeFetchTask = Task { [weak self] in
            guard let self = self else { return }

            let result = await self.loadFromNetwork(track: track, cleanTitle: cleanTitle, cleanArtist: cleanArtist)
            guard !Task.isCancelled, self.currentTrackKey == key else { return }

            self.storeInCache(key: key, result: result)
            self.applyResult(result)
            self.isLoading = false
        }
    }

    private func applyResult(_ result: CachedLyricsResult) {
        self.currentLyrics = result.lines
        self.isInstrumental = result.isInstrumental
        self.hasNoLyrics = result.hasNoLyrics
        self.isLoading = false
        self.lastActiveIndex = -1
        self.isMovingForward = true
    }

    public func resetState() {
        activeFetchTask?.cancel()
        activeFetchTask = nil
        currentLyrics = []
        isLoading = false
        isInstrumental = false
        hasNoLyrics = false
        lastActiveIndex = -1
        isMovingForward = true
    }

    /// Fast binary search for the active lyric line at the current playback position.
    public func activeIndex(for position: TimeInterval) -> Int? {
        guard !currentLyrics.isEmpty else { return nil }

        // If playback has not yet reached the first lyric line
        if position < currentLyrics[0].timestamp {
            if lastActiveIndex != -1 {
                isMovingForward = false
                lastActiveIndex = -1
            }
            return nil
        }

        var low = 0
        var high = currentLyrics.count - 1
        var match = 0

        while low <= high {
            let mid = (low + high) / 2
            if currentLyrics[mid].timestamp <= position {
                match = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }

        if match != lastActiveIndex {
            isMovingForward = match >= lastActiveIndex
            lastActiveIndex = match
        }

        return match
    }

    /// Returns the 3 lines (previous, current, next) around the active playback position.
    public func threeLines(for position: TimeInterval) -> (previous: String?, current: String?, next: String?) {
        guard !currentLyrics.isEmpty else {
            return (nil, nil, nil)
        }

        guard let active = activeIndex(for: position) else {
            // Before the first lyric line
            let next = currentLyrics.first?.text
            return (nil, "...", next)
        }

        let prev = active > 0 ? currentLyrics[active - 1].text : nil
        let curr = currentLyrics[active].text
        let nxt = active + 1 < currentLyrics.count ? currentLyrics[active + 1].text : nil

        return (prev, curr, nxt)
    }

    // MARK: - Networking

    private func loadFromNetwork(track: TrackInfo, cleanTitle: String, cleanArtist: String) async -> CachedLyricsResult {
        // Attempt 1: Clean Match with duration
        if let response = await queryGetEndpoint(title: cleanTitle, artist: cleanArtist, duration: track.duration) {
            return processResponse(response)
        }

        // Attempt 2: Clean Match without duration
        if let response = await queryGetEndpoint(title: cleanTitle, artist: cleanArtist, duration: nil) {
            return processResponse(response)
        }

        // Attempt 3: Raw Match (in case LRCLIB catalog matches original raw Spotify title/artist)
        if cleanTitle != track.title || cleanArtist != track.artist {
            if let response = await queryGetEndpoint(title: track.title, artist: track.artist, duration: track.duration) {
                return processResponse(response)
            }
        }

        // Attempt 4: Search endpoint fallback
        if let response = await querySearchEndpoint(query: "\(cleanTitle) \(cleanArtist)") {
            return processResponse(response)
        }

        return CachedLyricsResult(lines: [], isInstrumental: false, hasNoLyrics: true)
    }

    private func processResponse(_ response: LRCLIBResponse) -> CachedLyricsResult {
        if response.instrumental == true {
            return CachedLyricsResult(lines: [], isInstrumental: true, hasNoLyrics: false)
        }

        if let synced = response.syncedLyrics, !synced.isEmpty {
            let parsed = LRCParser.parse(synced)
            if !parsed.isEmpty {
                return CachedLyricsResult(lines: parsed, isInstrumental: false, hasNoLyrics: false)
            }
        }

        return CachedLyricsResult(lines: [], isInstrumental: false, hasNoLyrics: true)
    }

    private func queryGetEndpoint(title: String, artist: String, duration: TimeInterval?) async -> LRCLIBResponse? {
        var components = URLComponents(string: "https://lrclib.net/api/get")
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "track_name", value: title),
            URLQueryItem(name: "artist_name", value: artist)
        ]
        if let d = duration, d > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(d))))
        }
        components?.queryItems = queryItems

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("Notch/1.0 (https://github.com/notch)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(LRCLIBResponse.self, from: data)
        } catch {
            return nil
        }
    }

    private func querySearchEndpoint(query: String) async -> LRCLIBResponse? {
        var components = URLComponents(string: "https://lrclib.net/api/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query)
        ]

        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        request.setValue("Notch/1.0 (https://github.com/notch)", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await urlSession.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let results = try JSONDecoder().decode([LRCLIBResponse].self, from: data)
            return results.first(where: { $0.syncedLyrics != nil && !$0.syncedLyrics!.isEmpty })
        } catch {
            return nil
        }
    }

    public func sanitize(_ string: String) -> String {
        var clean = string
        // 1. Bracketed noise: (feat. ...), [Remastered], etc.
        if let regex = try? NSRegularExpression(pattern: #"\s*[\(\[][^()\[\]]*(?:\bfeat\b|\bft\b|remaster|deluxe|version|edit|mono|stereo)[^()\[\]]*[\)\]]"#, options: .caseInsensitive) {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }
        // 2. Unbracketed featuring credits: " - feat. ...", " ft. ...", " feat ..."
        if let regex = try? NSRegularExpression(pattern: #"\s*(?:-|–)?\s*\b(?:feat|ft)\.?(?:\s+.*$)"#, options: .caseInsensitive) {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }
        // 3. Trailing "- Radio Edit", "- Remastered ...", etc.
        if let regex = try? NSRegularExpression(pattern: #"\s*(?:-|–)\s*(?:Radio Edit|Remaster(?:ed)?(?:\s*\d+)?).*$"#, options: .caseInsensitive) {
            clean = regex.stringByReplacingMatches(in: clean, range: NSRange(location: 0, length: (clean as NSString).length), withTemplate: "")
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Preloaded Demo Lyrics (Guarantees immediate offline functionality)

    private func preloadDemoLyrics() {
        let midnightCityLrc = """
        [00:29.80] Waiting in a car
        [00:32.40] Waiting for a ride in the dark
        [00:37.40] The night city grows
        [00:40.80] Look and see her eyes, they look like mine
        [00:45.00] Waiting in a car
        [00:48.20] Waiting for a ride in the dark
        [00:53.00] The night city grows
        [00:56.50] Look and see her eyes, they look like mine
        [01:04.20] The city is my church
        [01:08.50] It wraps me in the blinding twilight
        [01:19.80] Waiting in a car
        [01:23.00] Waiting for a ride in the dark
        """

        let getLuckyLrc = """
        [00:30.64] Like the legend of the phoenix, huh
        [00:35.11] Our ends were beginnings
        [00:39.37] What keeps the planet spinning? Ah
        [00:43.69] The force from the beginning
        [00:47.36] Look
        [00:49.30] We've come too far
        [00:52.37] To give up who we are
        [00:56.95] So let's raise the bar
        [01:00.58] And our cups to the stars
        [01:06.04] She's up all night 'til the sun
        [01:07.72] I'm up all night to get some
        [01:10.03] She's up all night for good fun
        [01:12.28] I'm up all night to get lucky
        [01:13.87] We're up all night 'til the sun
        [01:16.15] We're up all night to get some
        [01:18.37] We're up all night for good fun
        [01:20.26] We're up all night to get lucky
        """

        let starboyLrc = """
        [00:08.10] I'm tryna put you in the worst mood, ah
        [00:11.80] P1 cleaner than your church shoes, ah
        [00:15.50] Milli point two just to hurt you, ah
        [00:19.20] All red Lamb' just to tease you, ah
        [00:23.00] None of these toys on lease too, ah
        [00:26.50] Made your whole year in a week too, yah
        [00:30.20] Main bitch out of your league too, ah
        [00:33.80] Side bitch out of your league too, ah
        [00:37.50] Look what you've done
        [00:41.20] I'm a motherfuckin' starboy
        """

        let solarPowerLrc = """
        [00:12.50] I hate the winter, can't stand the cold
        [00:15.80] I tend to cancel all the boys when I'm out in the snow
        [00:20.10] But when the summer comes, my baby, I'm a different girl
        [00:27.00] Turn it on, my solar power
        [00:33.50] Acid green, aquamarine
        [00:37.00] The girl with the sun in her eyes
        """

        storeInCache(key: "midnight city__m83", result: CachedLyricsResult(lines: LRCParser.parse(midnightCityLrc), isInstrumental: false, hasNoLyrics: false))
        storeInCache(key: "get lucky__daft punk", result: CachedLyricsResult(lines: LRCParser.parse(getLuckyLrc), isInstrumental: false, hasNoLyrics: false))
        storeInCache(key: "starboy__the weeknd", result: CachedLyricsResult(lines: LRCParser.parse(starboyLrc), isInstrumental: false, hasNoLyrics: false))
        storeInCache(key: "solar power__lorde", result: CachedLyricsResult(lines: LRCParser.parse(solarPowerLrc), isInstrumental: false, hasNoLyrics: false))
        storeInCache(key: "resonance__home", result: CachedLyricsResult(lines: [], isInstrumental: true, hasNoLyrics: false))
    }
}
