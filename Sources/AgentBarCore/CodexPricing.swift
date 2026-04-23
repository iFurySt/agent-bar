import Foundation

enum CodexPricing {
    struct Price {
        let input: Double
        let output: Double
        let cachedInput: Double?
    }

    private static let prices: [String: Price] = [
        "gpt-5": Price(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-codex": Price(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5-mini": Price(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5-nano": Price(input: 5e-8, output: 4e-7, cachedInput: 5e-9),
        "gpt-5-pro": Price(input: 1.5e-5, output: 1.2e-4, cachedInput: nil),
        "gpt-5.1": Price(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex": Price(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-max": Price(input: 1.25e-6, output: 1e-5, cachedInput: 1.25e-7),
        "gpt-5.1-codex-mini": Price(input: 2.5e-7, output: 2e-6, cachedInput: 2.5e-8),
        "gpt-5.2": Price(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.2-codex": Price(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.2-pro": Price(input: 2.1e-5, output: 1.68e-4, cachedInput: nil),
        "gpt-5.3-codex": Price(input: 1.75e-6, output: 1.4e-5, cachedInput: 1.75e-7),
        "gpt-5.3-codex-spark": Price(input: 0, output: 0, cachedInput: 0),
        "gpt-5.4": Price(input: 2.5e-6, output: 1.5e-5, cachedInput: 2.5e-7),
        "gpt-5.4-mini": Price(input: 7.5e-7, output: 4.5e-6, cachedInput: 7.5e-8),
        "gpt-5.4-nano": Price(input: 2e-7, output: 1.25e-6, cachedInput: 2e-8),
        "gpt-5.4-pro": Price(input: 3e-5, output: 1.8e-4, cachedInput: nil),
    ]

    static func normalizeCodexModel(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("openai/") {
            trimmed.removeFirst("openai/".count)
        }
        if prices[trimmed] != nil { return trimmed }
        if let range = trimmed.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) {
            let base = String(trimmed[..<range.lowerBound])
            if prices[base] != nil { return base }
        }
        return trimmed
    }

    static func codexCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        outputTokens: Int) -> Double?
    {
        let key = normalizeCodexModel(model)
        guard let price = prices[key] else { return nil }
        let cached = min(max(0, cachedInputTokens), max(0, inputTokens))
        let nonCached = max(0, inputTokens - cached)
        return Double(nonCached) * price.input
            + Double(cached) * (price.cachedInput ?? price.input)
            + Double(max(0, outputTokens)) * price.output
    }
}
