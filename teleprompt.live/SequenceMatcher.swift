import Foundation

struct Match {
    let a: Int
    let b: Int
    let size: Int
}

class SequenceMatcher {
    private var a: [String] = []
    private var b: [String] = []
    private var matchingBlocks: [Match]?
    
    init(a: String, b: String) {
        self.setSeqs(a: Array(a.map { String($0) }), b: Array(b.map { String($0) }))
    }
    
    func setSeqs(a: [String], b: [String]) {
        self.a = a
        self.b = b
        self.matchingBlocks = nil
    }
    
    private func chainB() -> [String: [Int]] {
        var b2j: [String: [Int]] = [:]
        for (i, elt) in b.enumerated() {
            if b2j[elt] != nil {
                b2j[elt]!.append(i)
            } else {
                b2j[elt] = [i]
            }
        }
        return b2j
    }
    
    func findLongestMatch(alo: Int, ahi: Int, blo: Int, bhi: Int) -> Match {
        let b2j = chainB()
        var besti = alo
        var bestj = blo
        var bestsize = 0
        
        var j2len: [Int: Int] = [:]
        
        for i in alo..<ahi {
            var newj2len: [Int: Int] = [:]
            if let bIndices = b2j[a[i]] {
                for j in bIndices {
                    if j < blo || j >= bhi {
                        continue
                    }
                    let k = (j2len[j-1] ?? 0) + 1
                    newj2len[j] = k
                    if k > bestsize {
                        besti = i - k + 1
                        bestj = j - k + 1
                        bestsize = k
                    }
                }
            }
            j2len = newj2len
        }
        
        return Match(a: besti, b: bestj, size: bestsize)
    }
    
    func getMatchingBlocks() -> [Match] {
        if let blocks = self.matchingBlocks {
            return blocks
        }
        
        var i = 0, j = 0
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
        let matches = getMatchingBlocks().map { $0.size }.reduce(0, +)
        return 2.0 * Double(matches) / Double(a.count + b.count)
    }
}
