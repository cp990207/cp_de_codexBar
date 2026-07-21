import Foundation

extension CostUsagePricing {
    // MARK: - Kimi

    /// Kimi Code CLI (kimi.com coding subscription) has no public per-token price; models.dev lists
    /// the kimi-for-coding family at $0. These are the Kimi open-platform list rates for the
    /// equivalent public models, used only to estimate what the usage would have cost.
    struct KimiPricing {
        /// Non-cached input rate (wire field `inputOther`). Unlike Codex, Kimi reports non-cached
        /// input directly — cached reads are a separate bucket, not a subset of input.
        let inputCostPerToken: Double
        let outputCostPerToken: Double
        let cacheReadInputCostPerToken: Double?
        /// Cache-write (cache creation) rate; nil bills writes at the uncached input rate.
        let cacheWriteInputCostPerToken: Double?
    }

    private static let kimi: [String: KimiPricing] = [
        // Mirrors kimi-k2.7-code ($0.95 / $4.00 / $0.19 per 1M).
        "kimi-for-coding": KimiPricing(
            inputCostPerToken: 9.5e-7,
            outputCostPerToken: 4e-6,
            cacheReadInputCostPerToken: 1.9e-7,
            cacheWriteInputCostPerToken: nil),
        // Mirrors kimi-k2.7-code-highspeed ($1.90 / $8.00 / $0.38 per 1M).
        "kimi-for-coding-highspeed": KimiPricing(
            inputCostPerToken: 1.9e-6,
            outputCostPerToken: 8e-6,
            cacheReadInputCostPerToken: 3.8e-7,
            cacheWriteInputCostPerToken: nil),
        // Mirrors kimi-k3 ($3.00 / $15.00 / $0.30 per 1M).
        "k3": KimiPricing(
            inputCostPerToken: 3e-6,
            outputCostPerToken: 1.5e-5,
            cacheReadInputCostPerToken: 3e-7,
            cacheWriteInputCostPerToken: nil),
    ]

    static func kimiBuiltInPricingFingerprint() -> String {
        var parts: [String] = []
        for model in self.kimi.keys.sorted() {
            guard let pricing = self.kimi[model] else { continue }
            parts.append([
                "model=\(model)",
                self.optionalKimiPricingFingerprint(pricing.inputCostPerToken),
                self.optionalKimiPricingFingerprint(pricing.outputCostPerToken),
                self.optionalKimiPricingFingerprint(pricing.cacheReadInputCostPerToken),
                self.optionalKimiPricingFingerprint(pricing.cacheWriteInputCostPerToken),
            ].joined(separator: "|"))
        }
        return parts.joined(separator: "\n")
    }

    private static func optionalKimiPricingFingerprint(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.17g", value)
    }

    /// Normalizes a wire model id (e.g. `kimi-code/kimi-for-coding`) to the pricing table key.
    static func normalizeKimiModel(_ model: String) -> String {
        var trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let slash = trimmed.firstIndex(of: "/") {
            trimmed = String(trimmed[trimmed.index(after: slash)...])
        }
        return trimmed
    }

    static func kimiCostUSD(
        model: String,
        inputTokens: Int,
        cachedInputTokens: Int,
        cacheWriteInputTokens: Int,
        outputTokens: Int) -> Double?
    {
        guard let pricing = self.kimi[self.normalizeKimiModel(model)] else { return nil }
        let cacheReadRate = pricing.cacheReadInputCostPerToken ?? pricing.inputCostPerToken
        let cacheWriteRate = pricing.cacheWriteInputCostPerToken ?? pricing.inputCostPerToken
        return (Double(max(0, inputTokens)) * pricing.inputCostPerToken)
            + (Double(max(0, cachedInputTokens)) * cacheReadRate)
            + (Double(max(0, cacheWriteInputTokens)) * cacheWriteRate)
            + (Double(max(0, outputTokens)) * pricing.outputCostPerToken)
    }
}
