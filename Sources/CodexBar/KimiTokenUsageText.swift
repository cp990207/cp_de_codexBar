import CodexBarCore
import Foundation

enum KimiTokenUsageText {
    /// One-line summary of today's local Kimi Code token usage (uncached input, output,
    /// cache reads, request count), shown under the weekly quota bar in place of the
    /// weekly request-count detail.
    static func todayDetail(entry: CostUsageDailyReport.Entry?) -> String? {
        guard let entry else { return nil }
        let input = UsageFormatter.tokenCountString(entry.inputTokens ?? 0)
        let output = UsageFormatter.tokenCountString(entry.outputTokens ?? 0)
        let cacheRead = UsageFormatter.tokenCountString(entry.cacheReadTokens ?? 0)
        return String(
            format: L("Today: in %@ · out %@ · cache read %@ · %lld requests"),
            input,
            output,
            cacheRead,
            Int64(entry.requestCount ?? 0))
    }
}
