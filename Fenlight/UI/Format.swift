import Foundation

enum Format {
    /// 999 → "999", 12_345 → "12.3K", 4_500_000 → "4.5M".
    static func compact(_ value: Double) -> String {
        let units = ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]
        var v = value.rounded(.down)
        var i = 0
        while abs(v) >= 1000, i < units.count - 1 {
            v /= 1000
            i += 1
        }
        if i == 0 { return String(Int(v)) }
        let digits = abs(v) >= 100 ? 0 : 1
        var s = String(format: "%.\(digits)f", v)
        if s.hasSuffix(".0") { s.removeLast(2) }
        return s + units[i]
    }

    /// 75 → "1m", 8100 → "2h 15m".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}
