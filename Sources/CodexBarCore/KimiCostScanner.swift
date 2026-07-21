import Foundation

/// Scans Kimi Code CLI session logs (`<KIMI_CODE_HOME>/sessions/** /wire.jsonl`, default
/// `~/.kimi-code/sessions`) and aggregates turn-level `usage.record` events into a
/// `CostUsageDailyReport`. Usage is estimated from local logs; costs use Kimi open-platform
/// list rates since the coding subscription itself is not metered per token.
enum KimiCostScanner {
    struct Options {
        /// Explicit Kimi Code home directory (the one containing `sessions/`). When nil,
        /// `KIMI_CODE_HOME` from `environment` is honored, then `~/.kimi-code`.
        var kimiCodeHome: URL?
        var cacheRoot: URL?
        var refreshMinIntervalSeconds: TimeInterval = 60
        var forceRescan: Bool = false
        var environment: [String: String]?

        init(
            kimiCodeHome: URL? = nil,
            cacheRoot: URL? = nil,
            refreshMinIntervalSeconds: TimeInterval = 60,
            forceRescan: Bool = false,
            environment: [String: String]? = nil)
        {
            self.kimiCodeHome = kimiCodeHome
            self.cacheRoot = cacheRoot
            self.refreshMinIntervalSeconds = refreshMinIntervalSeconds
            self.forceRescan = forceRescan
            self.environment = environment
        }
    }

    // MARK: - Entry points

    static func loadDailyReportCancellable(
        since: Date,
        until: Date,
        now: Date = Date(),
        options: Options = Options(),
        checkCancellation: CostUsageScanner.CancellationCheck?) throws -> CostUsageDailyReport
    {
        let range = CostUsageScanner.CostUsageDayRange(since: since, until: until)
        var cache = KimiCostCacheIO.load(cacheRoot: options.cacheRoot)
        let nowMs = Int64(now.timeIntervalSince1970 * 1000)
        let refreshMs = Int64(max(0, options.refreshMinIntervalSeconds) * 1000)
        let shouldRefresh = options.forceRescan
            || refreshMs == 0
            || cache.lastScanUnixMs == 0
            || nowMs - cache.lastScanUnixMs > refreshMs

        if shouldRefresh {
            try checkCancellation?()
            let root = self.sessionsRoot(options: options)
            let files = self.listWireFiles(root: root)
            let filePathsInScan = Set(files.map(\.path))

            for fileURL in files {
                try checkCancellation?()
                self.scanWireFile(fileURL: fileURL, forceRescan: options.forceRescan, cache: &cache)
            }
            try checkCancellation?()

            for key in cache.files.keys where !filePathsInScan.contains(key) {
                cache.files.removeValue(forKey: key)
            }

            cache.lastScanUnixMs = nowMs
            KimiCostCacheIO.save(cache: cache, cacheRoot: options.cacheRoot)
        }

        return self.buildReport(cache: cache, range: range)
    }

    // MARK: - Roots and file listing

    static func sessionsRoot(options: Options) -> URL {
        if let home = options.kimiCodeHome {
            return home.appendingPathComponent("sessions", isDirectory: true)
        }
        let env = options.environment ?? ProcessInfo.processInfo.environment
        if let override = env["KIMI_CODE_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty
        {
            return URL(fileURLWithPath: override).appendingPathComponent("sessions", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".kimi-code", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    private static func listWireFiles(root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator where url.lastPathComponent == "wire.jsonl" {
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Per-file scanning

    private static func scanWireFile(
        fileURL: URL,
        forceRescan: Bool,
        cache: inout KimiCostCache)
    {
        guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let mtime = values.contentModificationDate
        else { return }
        let mtimeMs = Int64(mtime.timeIntervalSince1970 * 1000)

        if !forceRescan,
           let cached = cache.files[fileURL.path],
           cached.size == size,
           cached.mtimeUnixMs == mtimeMs
        {
            return
        }

        let contributions = self.parseWireFile(fileURL: fileURL)
        cache.files[fileURL.path] = KimiFileUsage(
            mtimeUnixMs: mtimeMs,
            size: Int64(size),
            contributions: contributions)
    }

    private static func parseWireFile(fileURL: URL) -> [String: [String: KimiPackedUsage]] {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else { return [:] }
        var contributions: [String: [String: KimiPackedUsage]] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage.record\"") else { continue }
            guard let record = self.parseUsageRecord(line: line) else { continue }
            var day = contributions[record.dayKey] ?? [:]
            var usage = day[record.model] ?? KimiPackedUsage()
            usage.inputTokens += record.inputTokens
            usage.cacheReadTokens += record.cacheReadTokens
            usage.cacheCreationTokens += record.cacheCreationTokens
            usage.outputTokens += record.outputTokens
            usage.requestCount += 1
            day[record.model] = usage
            contributions[record.dayKey] = day
        }
        return contributions
    }

    private struct UsageRecord {
        let dayKey: String
        let model: String
        let inputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        let outputTokens: Int
    }

    private static func parseUsageRecord(line: Substring) -> UsageRecord? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              object["type"] as? String == "usage.record",
              object["usageScope"] as? String == "turn",
              let usage = object["usage"] as? [String: Any]
        else { return nil }

        let rawModel = (object["model"] as? String) ?? "unknown"
        let model = CostUsagePricing.normalizeKimiModel(rawModel)
        let dayKey = self.dayKey(forTimestamp: object["time"])

        return UsageRecord(
            dayKey: dayKey,
            model: model.isEmpty ? "unknown" : model,
            inputTokens: self.readNonNegativeInt(usage["inputOther"]),
            cacheReadTokens: self.readNonNegativeInt(usage["inputCacheRead"]),
            cacheCreationTokens: self.readNonNegativeInt(usage["inputCacheCreation"]),
            outputTokens: self.readNonNegativeInt(usage["output"]))
    }

    private static func dayKey(forTimestamp value: Any?) -> String {
        let raw = self.readInt64(value)
        guard raw > 0 else { return "unknown" }
        // Wire timestamps are epoch milliseconds; accept seconds defensively.
        let seconds = raw > 1_000_000_000_000 ? Double(raw) / 1000 : Double(raw)
        return CostUsageScanner.CostUsageDayRange.dayKey(from: Date(timeIntervalSince1970: seconds))
    }

    private static func readInt64(_ value: Any?) -> Int64 {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let double = value as? Double { return Int64(double) }
        return 0
    }

    private static func readNonNegativeInt(_ value: Any?) -> Int {
        Int(max(0, self.readInt64(value)))
    }

    // MARK: - Report building

    private static func buildReport(
        cache: KimiCostCache,
        range: CostUsageScanner.CostUsageDayRange) -> CostUsageDailyReport
    {
        var merged: [String: [String: KimiPackedUsage]] = [:]
        for file in cache.files.values {
            for (dayKey, models) in file.contributions
                where CostUsageScanner.CostUsageDayRange.isInRange(
                    dayKey: dayKey,
                    since: range.sinceKey,
                    until: range.untilKey)
            {
                var day = merged[dayKey] ?? [:]
                for (model, usage) in models {
                    var existing = day[model] ?? KimiPackedUsage()
                    existing.inputTokens += usage.inputTokens
                    existing.cacheReadTokens += usage.cacheReadTokens
                    existing.cacheCreationTokens += usage.cacheCreationTokens
                    existing.outputTokens += usage.outputTokens
                    existing.requestCount += usage.requestCount
                    day[model] = existing
                }
                merged[dayKey] = day
            }
        }

        var entries: [CostUsageDailyReport.Entry] = []
        var totalInput = 0
        var totalCacheRead = 0
        var totalCacheCreation = 0
        var totalOutput = 0
        var totalTokens = 0
        var totalCost: Double?
        var sawAnyCost = false

        for dayKey in merged.keys.sorted() {
            guard let models = merged[dayKey] else { continue }
            var input = 0
            var cacheRead = 0
            var cacheCreation = 0
            var output = 0
            var requests = 0
            var dayCost: Double?
            var breakdowns: [CostUsageDailyReport.ModelBreakdown] = []

            for model in models.keys.sorted() {
                guard let usage = models[model] else { continue }
                let cost = CostUsagePricing.kimiCostUSD(
                    model: model,
                    inputTokens: usage.inputTokens,
                    cachedInputTokens: usage.cacheReadTokens,
                    cacheWriteInputTokens: usage.cacheCreationTokens,
                    outputTokens: usage.outputTokens)
                if let cost {
                    dayCost = (dayCost ?? 0) + cost
                }
                breakdowns.append(CostUsageDailyReport.ModelBreakdown(
                    modelName: model,
                    costUSD: cost,
                    totalTokens: usage.totalTokens,
                    requestCount: usage.requestCount))

                input += usage.inputTokens
                cacheRead += usage.cacheReadTokens
                cacheCreation += usage.cacheCreationTokens
                output += usage.outputTokens
                requests += usage.requestCount
            }

            let dayTokens = input + cacheRead + cacheCreation + output
            entries.append(CostUsageDailyReport.Entry(
                date: dayKey,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead,
                cacheCreationTokens: cacheCreation,
                totalTokens: dayTokens,
                requestCount: requests,
                costUSD: dayCost,
                modelsUsed: models.keys.sorted(),
                modelBreakdowns: breakdowns))

            totalInput += input
            totalCacheRead += cacheRead
            totalCacheCreation += cacheCreation
            totalOutput += output
            totalTokens += dayTokens
            if let dayCost {
                totalCost = (totalCost ?? 0) + dayCost
                sawAnyCost = true
            }
        }

        let summary = CostUsageDailyReport.Summary(
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            cacheReadTokens: totalCacheRead,
            cacheCreationTokens: totalCacheCreation,
            totalTokens: totalTokens,
            totalCostUSD: sawAnyCost ? totalCost : nil)

        return CostUsageDailyReport(data: entries, summary: summary)
    }
}
