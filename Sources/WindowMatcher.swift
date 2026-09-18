import Foundation

enum WindowMatcher {
    struct Pair: Equatable {
        var savedIndex: Int
        var liveIndex: Int
        var score: Int
    }

    static func match(saved: [SavedWindow], liveKeys: [WindowMatchKey]) -> [Pair] {
        var candidates: [Pair] = []

        for (savedIndex, savedWindow) in saved.enumerated() {
            for (liveIndex, liveKey) in liveKeys.enumerated() {
                let score = score(savedWindow.matchKey, liveKey)
                if score > 0 {
                    candidates.append(Pair(savedIndex: savedIndex, liveIndex: liveIndex, score: score))
                }
            }
        }

        candidates.sort {
            if $0.score != $1.score {
                return $0.score > $1.score
            }
            if $0.savedIndex != $1.savedIndex {
                return $0.savedIndex < $1.savedIndex
            }
            return $0.liveIndex < $1.liveIndex
        }

        var usedSaved = Set<Int>()
        var usedLive = Set<Int>()
        var result: [Pair] = []

        for candidate in candidates {
            guard !usedSaved.contains(candidate.savedIndex),
                  !usedLive.contains(candidate.liveIndex) else {
                continue
            }
            usedSaved.insert(candidate.savedIndex)
            usedLive.insert(candidate.liveIndex)
            result.append(candidate)
        }

        return result.sorted { $0.savedIndex < $1.savedIndex }
    }

    static func score(_ saved: WindowMatchKey, _ live: WindowMatchKey) -> Int {
        guard saved.bundleIdentifier == live.bundleIdentifier else {
            return 0
        }

        var value = 10
        if let identifier = saved.identifier,
           !identifier.isEmpty,
           identifier == live.identifier {
            value += 120
        }
        if let documentHash = saved.documentHash,
           documentHash == live.documentHash {
            value += 90
        }
        if let titleHash = saved.titleHash,
           titleHash == live.titleHash {
            value += 70
        }
        if saved.role == live.role {
            value += 10
        }
        if saved.subrole == live.subrole {
            value += 10
        }
        if saved.ordinal == live.ordinal {
            value += 30
        } else {
            value -= min(abs(saved.ordinal - live.ordinal) * 3, 15)
        }
        return max(value, 1)
    }
}
