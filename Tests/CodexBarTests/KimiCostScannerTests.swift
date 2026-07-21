import Foundation
import Testing
@testable import CodexBarCore

struct KimiCostScannerTests {
    // MARK: - Fixtures

    private struct KimiTestHome {
        let root: URL
        let home: URL
        let cacheRoot: URL

        init() throws {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "codexbar-kimi-cost-\(UUID().uuidString)",
                isDirectory: true)
            self.root = root
            self.home = root.appendingPathComponent("kimi-home", isDirectory: true)
            self.cacheRoot = root.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: self.home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: self.root)
        }

        @discardableResult
        func writeWire(session: String, agent: String = "main", lines: [String]) throws -> URL {
            let dir = self.home
                .appendingPathComponent("sessions", isDirectory: true)
                .appendingPathComponent("wd_project_abcdef123456", isDirectory: true)
                .appendingPathComponent(session, isDirectory: true)
                .appendingPathComponent("agents", isDirectory: true)
                .appendingPathComponent(agent, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("wire.jsonl", isDirectory: false)
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func options(refreshMinIntervalSeconds: TimeInterval = 0) -> KimiCostScanner.Options {
            KimiCostScanner.Options(
                kimiCodeHome: self.home,
                cacheRoot: self.cacheRoot,
                refreshMinIntervalSeconds: refreshMinIntervalSeconds)
        }
    }

    private func localNoon(year: Int, month: Int, day: Int) throws -> Date {
        var comps = DateComponents()
        comps.calendar = Calendar.current
        comps.timeZone = TimeZone.current
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        guard let date = comps.date else { throw NSError(domain: "KimiCostScannerTests", code: 1) }
        return date
    }

    private func dayKey(_ date: Date) -> String {
        CostUsageScanner.CostUsageDayRange.dayKey(from: date)
    }

    private func usageRecord(
        model: String,
        time: Date,
        input: Int,
        cacheRead: Int,
        cacheCreation: Int = 0,
        output: Int,
        scope: String = "turn") -> String
    {
        let ms = Int64(time.timeIntervalSince1970 * 1000)
        return """
        {"type":"usage.record","model":"\(model)","usage":{"inputOther":\(input),"output":\(output),\
        "inputCacheRead":\(cacheRead),"inputCacheCreation":\(cacheCreation)},"usageScope":"\(scope)","time":\(ms)}
        """
    }

    // MARK: - Tests

    @Test
    func `aggregates turn usage by day and model across sessions and agents`() throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day1 = try self.localNoon(year: 2026, month: 7, day: 20)
        let day2 = try self.localNoon(year: 2026, month: 7, day: 21)
        try fixture.writeWire(session: "session-a", agent: "main", lines: [
            self.usageRecord(model: "kimi-code/kimi-for-coding", time: day1, input: 100, cacheRead: 1000, output: 10),
            self.usageRecord(model: "kimi-code/kimi-for-coding", time: day2, input: 200, cacheRead: 2000, output: 20),
        ])
        try fixture.writeWire(session: "session-a", agent: "agent-0", lines: [
            self.usageRecord(model: "kimi-code/kimi-for-coding", time: day1, input: 300, cacheRead: 3000, output: 30),
        ])
        try fixture.writeWire(session: "session-b", agent: "main", lines: [
            self.usageRecord(model: "kimi-code/k3", time: day1, input: 50, cacheRead: 500, output: 5),
        ])

        let report = try KimiCostScanner.loadDailyReportCancellable(
            since: day1.addingTimeInterval(-3600),
            until: day2.addingTimeInterval(3600),
            options: fixture.options(),
            checkCancellation: nil)

        #expect(report.data.count == 2)
        let entry1 = try #require(report.data.first { $0.date == self.dayKey(day1) })
        #expect(entry1.inputTokens == 450)
        #expect(entry1.cacheReadTokens == 4500)
        #expect(entry1.outputTokens == 45)
        #expect(entry1.requestCount == 3)
        #expect(entry1.modelsUsed == ["k3", "kimi-for-coding"])
        let coding = try #require(entry1.modelBreakdowns?.first { $0.modelName == "kimi-for-coding" })
        #expect(coding.requestCount == 2)
        #expect(coding.totalTokens == 400 + 4000 + 40)

        let entry2 = try #require(report.data.first { $0.date == self.dayKey(day2) })
        #expect(entry2.inputTokens == 200)
        #expect(entry2.requestCount == 1)
    }

    @Test
    func `ignores session scope records and non usage lines`() throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day = try self.localNoon(year: 2026, month: 7, day: 20)
        try fixture.writeWire(session: "session-a", lines: [
            self.usageRecord(model: "kimi-code/kimi-for-coding", time: day, input: 100, cacheRead: 1000, output: 10),
            self.usageRecord(
                model: "kimi-code/kimi-for-coding",
                time: day,
                input: 999,
                cacheRead: 9999,
                output: 99,
                scope: "session"),
            #"{"type":"context.append_loop_event","event":{"type":"step.end","usage":{"inputOther":5,"output":5}}}"#,
            "not json at all",
        ])

        let report = try KimiCostScanner.loadDailyReportCancellable(
            since: day.addingTimeInterval(-3600),
            until: day.addingTimeInterval(3600),
            options: fixture.options(),
            checkCancellation: nil)

        let entry = try #require(report.data.first)
        #expect(report.data.count == 1)
        #expect(entry.inputTokens == 100)
        #expect(entry.cacheReadTokens == 1000)
        #expect(entry.requestCount == 1)
    }

    @Test
    func `strips provider prefix from model names and keeps unknown models priceless`() throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day = try self.localNoon(year: 2026, month: 7, day: 20)
        try fixture.writeWire(session: "session-a", lines: [
            self.usageRecord(
                model: "kimi-code/kimi-for-coding",
                time: day,
                input: 1_000_000,
                cacheRead: 1_000_000,
                output: 1_000_000),
            self.usageRecord(model: "kimi-code/future-model-9", time: day, input: 10, cacheRead: 20, output: 5),
        ])

        let report = try KimiCostScanner.loadDailyReportCancellable(
            since: day.addingTimeInterval(-3600),
            until: day.addingTimeInterval(3600),
            options: fixture.options(),
            checkCancellation: nil)

        let entry = try #require(report.data.first)
        let known = try #require(entry.modelBreakdowns?.first { $0.modelName == "kimi-for-coding" })
        // ¥6.50 input + ¥1.30 cache read + ¥27.00 output per 1M tokens.
        #expect(try #require(known.costUSD) == 34.8)
        let unknown = try #require(entry.modelBreakdowns?.first { $0.modelName == "future-model-9" })
        #expect(unknown.costUSD == nil)
        #expect(unknown.totalTokens == 35)
        // Day cost only includes priceable models.
        #expect(try #require(entry.costUSD) == 34.8)
    }

    @Test
    func `honors KIMI_CODE_HOME from the provided environment`() throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day = try self.localNoon(year: 2026, month: 7, day: 20)
        try fixture.writeWire(session: "session-a", lines: [
            self.usageRecord(model: "kimi-code/k3", time: day, input: 100, cacheRead: 100, output: 10),
        ])

        var options = fixture.options()
        options.kimiCodeHome = nil
        options.environment = ["KIMI_CODE_HOME": fixture.home.path]
        let report = try KimiCostScanner.loadDailyReportCancellable(
            since: day.addingTimeInterval(-3600),
            until: day.addingTimeInterval(3600),
            options: options,
            checkCancellation: nil)

        #expect(report.data.first?.inputTokens == 100)
    }

    @Test
    func `skips unchanged files and rescans appended ones`() throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day = try self.localNoon(year: 2026, month: 7, day: 20)
        let first = self.usageRecord(model: "kimi-code/k3", time: day, input: 100, cacheRead: 100, output: 10)
        let wireURL = try fixture.writeWire(session: "session-a", lines: [first])
        let options = fixture.options()

        func scan() throws -> CostUsageDailyReport {
            try KimiCostScanner.loadDailyReportCancellable(
                since: day.addingTimeInterval(-3600),
                until: day.addingTimeInterval(3600),
                options: options,
                checkCancellation: nil)
        }

        #expect(try scan().data.first?.inputTokens == 100)
        // Second scan hits the per-file cache but still reports the same totals.
        #expect(try scan().data.first?.inputTokens == 100)

        let second = self.usageRecord(model: "kimi-code/k3", time: day, input: 200, cacheRead: 200, output: 20)
        try [first, second].joined(separator: "\n").write(to: wireURL, atomically: true, encoding: .utf8)
        #expect(try scan().data.first?.inputTokens == 300)
        #expect(try scan().data.first?.requestCount == 2)
    }

    @Test
    func `fetcher returns a kimi token snapshot`() async throws {
        let fixture = try KimiTestHome()
        defer { fixture.cleanup() }

        let day = try self.localNoon(year: 2026, month: 7, day: 20)
        try fixture.writeWire(session: "session-a", lines: [
            self.usageRecord(model: "kimi-code/kimi-for-coding", time: day, input: 100, cacheRead: 1000, output: 10),
        ])

        let snapshot = try await CostUsageFetcher.loadTokenSnapshot(
            provider: .kimi,
            environment: ["KIMI_CODE_HOME": fixture.home.path],
            now: day,
            historyDays: 30,
            refreshPricingInBackground: false,
            scannerOptions: CostUsageScanner.Options(cacheRoot: fixture.cacheRoot))

        let entry = try #require(snapshot.daily.first { $0.date == self.dayKey(day) })
        #expect(entry.inputTokens == 100)
        #expect(entry.modelBreakdowns?.first?.modelName == "kimi-for-coding")
        #expect(snapshot.sessionTokens == 1110)
        #expect(snapshot.sessionCostUSD != nil)
        #expect(snapshot.currencyCode == "CNY")
        #expect(snapshot.projects.isEmpty)
    }
}
