import Foundation

/// A tiny deterministic random number generator (SplitMix64). Its state is stored in the save,
/// so summons and arrival times can't be re-rolled by restarting the app, and tests are repeatable.
struct SeededRandom {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// A number in 0..<1.
    mutating func unit() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }

    mutating func range(_ r: ClosedRange<Double>) -> Double {
        r.lowerBound + unit() * (r.upperBound - r.lowerBound)
    }

    mutating func pick<T>(_ items: [T]) -> T? {
        guard !items.isEmpty else { return nil }
        return items[Int(unit() * Double(items.count)) % items.count]
    }

    /// Picks one item, where each item's chance is proportional to its weight.
    mutating func weighted<T>(_ items: [(T, Double)]) -> T? {
        let total = items.reduce(0) { $0 + max(0, $1.1) }
        guard total > 0 else { return nil }
        var roll = unit() * total
        for (item, weight) in items where weight > 0 {
            if roll < weight { return item }
            roll -= weight
        }
        return items.last { $0.1 > 0 }?.0
    }
}
