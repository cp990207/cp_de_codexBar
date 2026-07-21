import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct KimiTokenUsageTextTests {
    @Test
    func `today detail formats input output cache read and requests`() throws {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-07-21",
            inputTokens: 1_400_000,
            outputTokens: 264_000,
            cacheReadTokens: 35_600_000,
            cacheCreationTokens: 0,
            totalTokens: 37_264_000,
            requestCount: 151,
            costUSD: 42.5,
            modelsUsed: ["kimi-for-coding"],
            modelBreakdowns: nil)

        let detail = try #require(KimiTokenUsageText.todayDetail(entry: entry))
        #expect(detail.contains(UsageFormatter.tokenCountString(1_400_000)))
        #expect(detail.contains(UsageFormatter.tokenCountString(264_000)))
        #expect(detail.contains(UsageFormatter.tokenCountString(35_600_000)))
        #expect(detail.contains("151"))
    }

    @Test
    func `today detail is nil without an entry`() {
        #expect(KimiTokenUsageText.todayDetail(entry: nil) == nil)
    }

    @Test
    func `today detail tolerates missing token fields`() throws {
        let entry = CostUsageDailyReport.Entry(
            date: "2026-07-21",
            inputTokens: nil,
            outputTokens: nil,
            totalTokens: nil,
            costUSD: nil,
            modelsUsed: nil,
            modelBreakdowns: nil)

        let detail = try #require(KimiTokenUsageText.todayDetail(entry: entry))
        #expect(detail.contains("0"))
    }
}
