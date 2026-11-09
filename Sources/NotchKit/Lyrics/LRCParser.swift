import Foundation

/// Fast parser for LRC (LyRiCs) formatted text strings into synchronized `LyricLine` collections.
public enum LRCParser {
    // Matches [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
    private static let tagRegex = try? NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]", options: [])

    public static func parse(_ lrcContent: String) -> [LyricLine] {
        guard let tagRegex = tagRegex else { return [] }
        var parsed: [(timestamp: TimeInterval, text: String)] = []
        let lines = lrcContent.components(separatedBy: .newlines)

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            let nsLine = line as NSString
            let fullRange = NSRange(location: 0, length: nsLine.length)
            let matches = tagRegex.matches(in: line, options: [], range: fullRange)
            guard !matches.isEmpty else { continue }

            // Extract the lyric text following all timestamp tags
            var lastTagEnd = 0
            for match in matches {
                lastTagEnd = max(lastTagEnd, match.range.location + match.range.length)
            }

            let text = nsLine.substring(from: lastTagEnd).trimmingCharacters(in: .whitespaces)

            // Extract each timestamp associated with this line
            for match in matches {
                guard match.numberOfRanges >= 3 else { continue }
                let minRange = match.range(at: 1)
                let secRange = match.range(at: 2)

                let minutes = Double(nsLine.substring(with: minRange)) ?? 0.0
                let seconds = Double(nsLine.substring(with: secRange)) ?? 0.0

                var milliseconds: Double = 0.0
                if match.numberOfRanges >= 4, match.range(at: 3).location != NSNotFound {
                    let msStr = nsLine.substring(with: match.range(at: 3))
                    if let msVal = Double(msStr) {
                        if msStr.count == 1 {
                            milliseconds = msVal / 10.0
                        } else if msStr.count == 2 {
                            milliseconds = msVal / 100.0
                        } else {
                            milliseconds = msVal / 1000.0
                        }
                    }
                }

                let timestamp = (minutes * 60.0) + seconds + milliseconds
                parsed.append((timestamp: timestamp, text: text))
            }
        }

        // Sort chronologically and assign stable sequential IDs
        parsed.sort { $0.timestamp < $1.timestamp }

        // Filter out empty lines to keep the 3-line display meaningful
        let filtered = parsed.filter { !$0.text.isEmpty }

        return filtered.enumerated().map { index, item in
            LyricLine(id: index, timestamp: item.timestamp, text: item.text)
        }
    }
}
