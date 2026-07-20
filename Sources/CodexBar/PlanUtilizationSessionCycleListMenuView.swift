import CodexBarCore
import SwiftUI

/// Lists recent 5-hour rate-limit cycles with the peak percent consumed in each cycle.
/// Derived from the `session` plan-utilization history series; shown below the Plan Usage chart
/// for any provider that records a session window (Claude, Codex, Kimi, ...).
@MainActor
struct PlanUtilizationSessionCycleListMenuView: View {
    struct SessionCycle: Equatable {
        let boundaryDate: Date
        let usedPercent: Double
    }

    private enum Layout {
        static let maxCycles = 8
    }

    private let cycles: [SessionCycle]
    private let width: CGFloat

    init?(histories: [PlanUtilizationSeriesHistory], width: CGFloat) {
        guard let history = Self.sessionHistory(histories: histories) else { return nil }
        let cycles = Self.sessionCycles(history: history, limit: Layout.maxCycles)
        guard !cycles.isEmpty else { return nil }
        self.cycles = cycles
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Recent 5-Hour Cycles"))
                .font(.footnote)
                .foregroundStyle(.secondary)
            ForEach(self.cycles, id: \.boundaryDate) { cycle in
                Text(Self.cycleLine(cycle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: self.width, maxWidth: .infinity, alignment: .topLeading)
        .accessibilityLabel(L("Recent 5-Hour Cycles"))
    }

    nonisolated static func sessionHistory(histories: [PlanUtilizationSeriesHistory]) -> PlanUtilizationSeriesHistory? {
        let matching = histories.filter {
            $0.name == .session && $0.windowMinutes > 0 && !$0.entries.isEmpty
        }
        guard let first = matching.first else { return nil }
        guard matching.count > 1 else { return first }
        return PlanUtilizationSeriesHistory(
            name: first.name,
            windowMinutes: first.windowMinutes,
            entries: matching.flatMap(\.entries))
    }

    /// Peak percent consumed per reset cycle, newest first. Entries snap to the reset-boundary
    /// lattice anchored at the latest observed `resetsAt` (mirroring the chart), so small
    /// server-side drift of `resetsAt` within a cycle does not split it.
    nonisolated static func sessionCycles(history: PlanUtilizationSeriesHistory, limit: Int) -> [SessionCycle] {
        guard history.windowMinutes > 0, limit > 0 else { return [] }
        let windowInterval = Double(history.windowMinutes) * 60
        let anchor = history.entries
            .compactMap(\.resetsAt)
            .map { floor($0.timeIntervalSince1970) }
            .max()

        var peakByBoundary: [Double: Double] = [:]
        for entry in history.entries {
            let boundary: Double
            if let anchor {
                if let resetsAt = entry.resetsAt {
                    let offset = floor(resetsAt.timeIntervalSince1970) - anchor
                    boundary = anchor + (offset / windowInterval).rounded() * windowInterval
                } else {
                    let offset = floor(entry.capturedAt.timeIntervalSince1970) - anchor
                    boundary = anchor + (offset / windowInterval).rounded(.up) * windowInterval
                }
            } else if let resetsAt = entry.resetsAt {
                boundary = floor(resetsAt.timeIntervalSince1970)
            } else {
                let bucket = floor(entry.capturedAt.timeIntervalSince1970 / windowInterval)
                boundary = (bucket + 1) * windowInterval
            }
            let percent = max(0, min(100, entry.usedPercent))
            peakByBoundary[boundary] = max(peakByBoundary[boundary] ?? 0, percent)
        }

        return peakByBoundary
            .sorted { $0.key > $1.key }
            .prefix(limit)
            .map { SessionCycle(boundaryDate: Date(timeIntervalSince1970: $0.key), usedPercent: $0.value) }
    }

    private nonisolated static func cycleLine(_ cycle: SessionCycle) -> String {
        let usedText = cycle.usedPercent.formatted(.number.precision(.fractionLength(0...1)))
        return L("%@: %@%% used", self.dateLabel(for: cycle.boundaryDate), usedText)
    }

    private nonisolated static func dateLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = codexBarLocalizedLocale()
        formatter.timeZone = TimeZone.current
        formatter.setLocalizedDateFormatFromTemplate("MMM d, h:mm a")
        var rendered = formatter.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
        let amSymbol = formatter.amSymbol ?? ""
        let pmSymbol = formatter.pmSymbol ?? ""
        if !amSymbol.isEmpty {
            rendered = rendered.replacingOccurrences(of: amSymbol, with: amSymbol.lowercased())
        }
        if !pmSymbol.isEmpty {
            rendered = rendered.replacingOccurrences(of: pmSymbol, with: pmSymbol.lowercased())
        }
        return rendered
    }

    #if DEBUG
    nonisolated static func _sessionCyclesForTesting(
        histories: [PlanUtilizationSeriesHistory],
        limit: Int = Layout.maxCycles) -> [SessionCycle]
    {
        guard let history = self.sessionHistory(histories: histories) else { return [] }
        return self.sessionCycles(history: history, limit: limit)
    }
    #endif
}
