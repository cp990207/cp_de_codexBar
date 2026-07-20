import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

struct PlanUtilizationSessionCycleListMenuViewTests {
    @Test
    func `groups entries into cycles by reset boundary and keeps peak`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: base, usedPercent: 20, resetsAt: base.addingTimeInterval(5 * 3600)),
            planEntry(
                at: base.addingTimeInterval(3600),
                usedPercent: 55,
                resetsAt: base.addingTimeInterval(5 * 3600)),
            planEntry(
                at: base.addingTimeInterval(6 * 3600),
                usedPercent: 30,
                resetsAt: base.addingTimeInterval(10 * 3600)),
        ])]

        let cycles = PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(histories: histories)

        #expect(cycles.count == 2)
        // Newest cycle first.
        #expect(cycles[0].boundaryDate == base.addingTimeInterval(10 * 3600))
        #expect(cycles[0].usedPercent == 30)
        #expect(cycles[1].boundaryDate == base.addingTimeInterval(5 * 3600))
        #expect(cycles[1].usedPercent == 55)
    }

    @Test
    func `snaps small reset boundary drift into the same cycle`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: base, usedPercent: 20, resetsAt: base.addingTimeInterval(5 * 3600)),
            planEntry(
                at: base.addingTimeInterval(3600),
                usedPercent: 70,
                resetsAt: base.addingTimeInterval(5 * 3600 + 120)),
        ])]

        let cycles = PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(histories: histories)

        #expect(cycles.count == 1)
        #expect(cycles[0].usedPercent == 70)
    }

    @Test
    func `buckets entries without reset boundary onto the lattice`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(
                at: base.addingTimeInterval(2 * 3600),
                usedPercent: 40,
                resetsAt: base.addingTimeInterval(5 * 3600)),
            planEntry(at: base.addingTimeInterval(7 * 3600), usedPercent: 25),
        ])]

        let cycles = PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(histories: histories)

        #expect(cycles.count == 2)
        #expect(cycles[0].boundaryDate == base.addingTimeInterval(10 * 3600))
        #expect(cycles[0].usedPercent == 25)
        #expect(cycles[1].boundaryDate == base.addingTimeInterval(5 * 3600))
        #expect(cycles[1].usedPercent == 40)
    }

    @Test
    func `falls back to epoch buckets when no reset boundary is known`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: [
            planEntry(at: base, usedPercent: 50),
            planEntry(at: base.addingTimeInterval(20 * 3600), usedPercent: 70),
        ])]

        let cycles = PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(histories: histories)

        #expect(cycles.count == 2)
        #expect(cycles[0].usedPercent == 70)
        #expect(cycles[1].usedPercent == 50)
    }

    @Test
    func `keeps only the most recent cycles up to the limit`() {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        var entries: [PlanUtilizationHistoryEntry] = []
        for index in 0..<10 {
            entries.append(planEntry(
                at: base.addingTimeInterval(Double(index) * 5 * 3600),
                usedPercent: Double(10 + index),
                resetsAt: base.addingTimeInterval(Double(index + 1) * 5 * 3600)))
        }
        let histories = [planSeries(name: .session, windowMinutes: 300, entries: entries)]

        let cycles = PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(
            histories: histories,
            limit: 8)

        #expect(cycles.count == 8)
        #expect(cycles.first?.usedPercent == 19)
        #expect(cycles.last?.usedPercent == 12)
    }

    @Test
    func `ignores non session series`() {
        let histories = [planSeries(name: .weekly, windowMinutes: 10080, entries: [
            planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 48),
        ])]

        #expect(PlanUtilizationSessionCycleListMenuView._sessionCyclesForTesting(histories: histories).isEmpty)
    }

    @MainActor
    @Test
    func `kimi chart shows five hour session tab`() {
        let histories = [
            planSeries(name: .session, windowMinutes: 300, entries: [
                planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 55),
            ]),
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: Date(timeIntervalSince1970: 1_700_086_400), usedPercent: 30),
            ]),
        ]
        let snapshot = UsageStorePlanUtilizationTests.makeKimiSnapshot(
            sessionReset: Date(timeIntervalSince1970: 1_700_018_000),
            weeklyReset: Date(timeIntervalSince1970: 1_700_086_400))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: histories,
            provider: .kimi,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["session:300", "weekly:10080"])
        #expect(model.seriesTitles == ["5-Hour", "7-Day"])
        #expect(model.selectedSeries == "session:300")
    }

    @MainActor
    @Test
    func `kimi chart shows weekly tab from primary quota without code 7d extra window`() {
        let histories = [
            planSeries(name: .session, windowMinutes: 300, entries: [
                planEntry(at: Date(timeIntervalSince1970: 1_700_000_000), usedPercent: 55),
            ]),
            planSeries(name: .weekly, windowMinutes: 10080, entries: [
                planEntry(at: Date(timeIntervalSince1970: 1_700_086_400), usedPercent: 40),
            ]),
        ]
        // API-key auth snapshot: primary weekly quota (no windowMinutes), no Code 7-day extra window.
        let snapshot = UsageSnapshot(
            primary: RateWindow(
                usedPercent: 40,
                windowMinutes: nil,
                resetsAt: Date(timeIntervalSince1970: 1_700_086_400),
                resetDescription: "200/500 requests"),
            secondary: RateWindow(
                usedPercent: 55,
                windowMinutes: 300,
                resetsAt: Date(timeIntervalSince1970: 1_700_018_000),
                resetDescription: "Rate: 13/20 per 5 hours"),
            tertiary: nil,
            extraRateWindows: nil,
            providerCost: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            identity: ProviderIdentitySnapshot(
                providerID: .kimi,
                accountEmail: nil,
                accountOrganization: nil,
                loginMethod: nil))

        let model = PlanUtilizationHistoryChartMenuView._modelSnapshotForTesting(
            histories: histories,
            provider: .kimi,
            snapshot: snapshot)

        #expect(model.visibleSeries == ["session:300", "weekly:10080"])
        #expect(model.seriesTitles == ["5-Hour", "7-Day"])
    }
}
