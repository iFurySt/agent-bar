import Foundation

public enum AgentBarDisplayFormatting {
    public static func line(snapshot: AgentBarSnapshot) -> String {
        let dot = "\u{00B7}"
        let quota = snapshot.rateLimits.availableWindows.map { window in
            "\(window.displayLabel(fallback: "Usage")) \(percent(window.remainingPercent))"
        }.joined(separator: "  ")
        let usage = "Today: \(usd(snapshot.costs.todayCostUSD)) \(dot) \(tokens(snapshot.costs.todayTokens))/~30 Days: \(usd(snapshot.costs.last30DaysCostUSD)) \(dot) \(tokens(snapshot.costs.last30DaysTokens)) Tokens"
        return quota.isEmpty ? usage : "\(quota)  \(usage)"
    }

    public static func percent(_ value: Int?) -> String {
        guard let value else { return "--%" }
        return "\(min(100, max(0, value)))%"
    }

    public static func usd(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        formatter.decimalSeparator = "."
        return "$" + (formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value))
    }

    public static func tokens(_ value: Int) -> String {
        let number = Double(value)
        if value >= 1_000_000_000 {
            return compact(number / 1_000_000_000, suffix: "B")
        }
        if value >= 1_000_000 {
            return compact(number / 1_000_000, suffix: "M", decimals: 0)
        }
        if value >= 1_000 {
            return compact(number / 1_000, suffix: "K")
        }
        return "\(value)"
    }

    private static func compact(_ value: Double, suffix: String, decimals: Int = 1) -> String {
        var text = String(format: "%.\(decimals)f", value)
        if text.hasSuffix(".0") {
            text.removeLast(2)
        }
        return text + suffix
    }
}

struct AgentBarError: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
