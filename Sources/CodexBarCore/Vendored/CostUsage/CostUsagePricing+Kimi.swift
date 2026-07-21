import Foundation

extension CostUsagePricing {
    // MARK: - Kimi

    /// Kimi Code CLI (kimi.com coding subscription) is not metered per token. These are the Kimi
    /// open-platform CN list rates (platform.kimi.com, CNY per token) for the equivalent public
    /// models, used only to estimate what the usage would have cost.
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
        // Mirrors kimi-k2.7-code CN list rates (¥6.50 / ¥27.00 / ¥1.30 per 1M).
        "kimi-for-coding": KimiPricing(
            inputCostPerToken: 6.5e-6,
            outputCostPerToken: 2.7e-5,
            cacheReadInputCostPerToken: 1.3e-6,
            cacheWriteInputCostPerToken: nil),
        // Mirrors kimi-k2.7-code-highspeed CN list rates (¥13.00 / ¥54.00 / ¥2.60 per 1M).
        "kimi-for-coding-highspeed": KimiPricing(
            inputCostPerToken: 1.3e-5,
            outputCostPerToken: 5.4e-5,
            cacheReadInputCostPerToken: 2.6e-6,
            cacheWriteInputCostPerToken: nil),
        // Mirrors kimi-k3 CN list rates (¥20.00 / ¥100.00 / ¥2.00 per 1M).
        "k3": KimiPricing(
            inputCostPerToken: 2e-5,
            outputCostPerToken: 1e-4,
            cacheReadInputCostPerToken: 2e-6,
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

    /// Estimated cost in CNY at Kimi open-platform CN list rates; nil when the model is unknown.
    static func kimiCostCNY(
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
