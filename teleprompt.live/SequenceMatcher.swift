import Foundation

struct Match {
    let a: Int
    let b: Int
    let size: Int
}

/// Port of Python difflib.SequenceMatcher (without autojunk) over characters.
/// Characters are interned to Ints and the b-index is built once, so scoring
/// a transcript against every sentence stays cheap enough to run on each
/// live (volatile) transcription update.
final class SequenceMatcher {
    private let a: [Int]
    private let b: [Int]
    private let b2j: [Int: [Int]]
    private var matchingBlocks: [Match]?

    init(a: String, b: String) {
        var codes: [Character: Int] = [:]
        func intern(_ s: String) -> [Int] {
            s.map { ch in
                if let c = codes[ch] { return c }
                let c = codes.count
                codes[ch] = c
                return c
            }
        }
        self.a = intern(a)
        self.b = intern(b)
        var b2j: [Int: [Int]] = [:]
        for (j, elt) in self.b.enumerated() {
            b2j[elt, default: []].append(j)
        }
        self.b2j = b2j
    }

    func findLongestMatch(alo: Int, ahi: Int, blo: Int, bhi: Int) -> Match {
        var besti = alo
        var bestj = blo
        var bestsize = 0
        // j2len[j + 1] = length of the match ending at a[i-1], b[j]; index 0
        // is the "j - 1 == -1" sentinel. Two rows, cleared via touched lists.
        var j2len = [Int](repeating: 0, count: b.count + 1)
        var newj2len = [Int](repeating: 0, count: b.count + 1)
        var touched: [Int] = []
        var newTouched: [Int] = []

        for i in alo..<ahi {
            if let bIndices = b2j[a[i]] {
                for j in bIndices where j >= blo && j < bhi {
                    let k = j2len[j] + 1
                    newj2len[j + 1] = k
                    newTouched.append(j + 1)
                    if k > bestsize {
                        besti = i - k + 1
                        bestj = j - k + 1
                        bestsize = k
                    }
                }
            }
            for t in touched { j2len[t] = 0 }
            swap(&j2len, &newj2len)
            swap(&touched, &newTouched)
            newTouched.removeAll(keepingCapacity: true)
        }

        return Match(a: besti, b: bestj, size: bestsize)
    }

    func getMatchingBlocks() -> [Match] {
        if let blocks = self.matchingBlocks {
            return blocks
        }

        let la = a.count
        let lb = b.count
        var queue: [(Int, Int, Int, Int)] = [(0, la, 0, lb)]
        var matchingBlocks: [Match] = []

        while !queue.isEmpty {
            let (alo, ahi, blo, bhi) = queue.removeLast()
            let match = findLongestMatch(alo: alo, ahi: ahi, blo: blo, bhi: bhi)
            if match.size != 0 {
                matchingBlocks.append(match)
                if alo < match.a && blo < match.b {
                    queue.append((alo, match.a, blo, match.b))
                }
                if match.a + match.size < ahi && match.b + match.size < bhi {
                    queue.append((match.a + match.size, ahi, match.b + match.size, bhi))
                }
            }
        }

        matchingBlocks.append(Match(a: la, b: lb, size: 0))
        self.matchingBlocks = matchingBlocks
        return matchingBlocks
    }

    func ratio() -> Double {
        let total = a.count + b.count
        guard total > 0 else { return 1.0 }
        let matches = getMatchingBlocks().map { $0.size }.reduce(0, +)
        return 2.0 * Double(matches) / Double(total)
    }
}
