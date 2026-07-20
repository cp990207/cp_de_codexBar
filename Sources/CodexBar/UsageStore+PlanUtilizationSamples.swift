import CodexBarCore
import Foundation

extension UsageStore {
    struct PlanUtilizationSeriesKey: Hashable {
        let name: PlanUtilizationSeriesName
        let windowMinutes: Int
    }

    struct PlanUtilizationSeriesSample {
        let name: PlanUtilizationSeriesName
        let windowMinutes: Int
        let entry: PlanUtilizationHistoryEntry
    }

    private nonisolated static let weeklyWindowMinutes = 7 * 24 * 60

    func planUtilizationSeriesSamples(
        provider: UsageProvider,
        snapshot: UsageSnapshot,
        capturedAt: Date) -> [PlanUtilizationSeriesSample]
    {
        var samplesByKey: [PlanUtilizationSeriesKey: PlanUtilizationSeriesSample] = [:]

        func appendWindow(
            _ window: RateWindow?,
            name: PlanUtilizationSeriesName?,
            fallbackWindowMinutes: Int? = nil)
        {
            guard let name,
                  let window,
                  let windowMinutes = window.windowMinutes ?? fallbackWindowMinutes,
                  windowMinutes > 0,
                  let usedPercent = Self.clampedPercent(window.usedPercent)
            else {
                return
            }

            let canonicalWindowMinutes = name.canonicalWindowMinutes(windowMinutes)
            let key = PlanUtilizationSeriesKey(name: name, windowMinutes: canonicalWindowMinutes)
            samplesByKey[key] = PlanUtilizationSeriesSample(
                name: name,
                windowMinutes: canonicalWindowMinutes,
                entry: PlanUtilizationHistoryEntry(
                    capturedAt: capturedAt,
                    usedPercent: usedPercent,
                    resetsAt: window.resetsAt))
        }

        func appendWeeklyWindow() {
            let standardWeeklyWindow = [snapshot.primary, snapshot.secondary, snapshot.tertiary]
                .compactMap(\.self)
                .first { $0.windowMinutes == Self.weeklyWindowMinutes }
            let extraWeeklyWindow = snapshot.extraRateWindows?
                .lazy
                .first { $0.usageKnown && $0.window.windowMinutes == Self.weeklyWindowMinutes }?
                .window
            if let weeklyWindow = standardWeeklyWindow ?? extraWeeklyWindow {
                appendWindow(weeklyWindow, name: .weekly)
            }
        }

        switch provider {
        case .codex:
            let projection = self.codexConsumerProjection(
                surface: .liveCard,
                snapshotOverride: snapshot,
                now: capturedAt)
            for lane in projection.planUtilizationLanes {
                appendWindow(lane.window, name: lane.role)
            }
        case .claude:
            appendWindow(snapshot.primary, name: .session)
            appendWindow(snapshot.secondary, name: .weekly)
            appendWindow(snapshot.tertiary, name: .opus)
        case .antigravity:
            let namedWeeklyWindows = snapshot.extraRateWindows?
                .filter {
                    $0.usageKnown
                        && $0.id.hasPrefix("antigravity-quota-summary-")
                        && $0.window.windowMinutes == Self.weeklyWindowMinutes
                }
                .map(\.window) ?? []
            if let mostUsedWeeklyWindow = namedWeeklyWindows.max(by: { $0.usedPercent < $1.usedPercent }) {
                appendWindow(mostUsedWeeklyWindow, name: .weekly)
            } else {
                for window in [snapshot.primary, snapshot.secondary, snapshot.tertiary] {
                    guard let window, window.windowMinutes == Self.weeklyWindowMinutes else { continue }
                    appendWindow(window, name: .weekly)
                }
            }
        case .kimi:
            // Kimi's 5-hour rate limit rides in `secondary`. The primary weekly quota is the weekly
            // bar the menu shows and exists for both auth modes, but it carries no windowMinutes —
            // bucket it with the canonical 7-day window (the reset lattice anchors on `resetsAt`).
            appendWindow(snapshot.secondary, name: .session)
            appendWindow(snapshot.primary, name: .weekly, fallbackWindowMinutes: Self.weeklyWindowMinutes)
        default:
            appendWeeklyWindow()
        }

        return samplesByKey.values.sorted { lhs, rhs in
            if lhs.windowMinutes != rhs.windowMinutes {
                return lhs.windowMinutes < rhs.windowMinutes
            }
            return lhs.name.rawValue < rhs.name.rawValue
        }
    }
}
