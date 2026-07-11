import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

extension StatusMenuTests {
    @Test
    func `overview rows expose a hosted-subview submenu recognized by isHostedSubviewMenu`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .openai
        settings.mergedMenuLastSelectedWasOverview = true
        settings.costUsageEnabled = true
        settings.costSummaryDisplayStyle = .both

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .openai || provider == .codex
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = OpenAIAPIUsageSnapshot(
            daily: [
                OpenAIAPIUsageSnapshot.DailyBucket(
                    day: "2023-11-14",
                    startTime: now,
                    endTime: now.addingTimeInterval(86400),
                    costUSD: 9,
                    requests: 12,
                    inputTokens: 100,
                    cachedInputTokens: 0,
                    outputTokens: 50,
                    totalTokens: 150,
                    lineItems: [],
                    models: []),
            ],
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .openai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        // Overview rows hover-open a hosted-subview submenu (native NSMenu auto-expand-on-hover)
        // showing the provider's full detail; there is no click-through navigation.
        let openAIRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-openai"
        })
        let submenu = try #require(openAIRow.submenu)
        #expect(controller.isHostedSubviewMenu(submenu))
        #expect(openAIRow.action == nil || openAIRow.target === controller)
        // No tab-bar-like first item: Overview rows are the merged menu's direct top-level content.
        #expect((menu.items.first?.representedObject as? String)?.hasPrefix("overviewRow-") == true)
    }

    @Test
    func `hovering an overview row hydrates the provider detail submenu with header and actions`() async throws {
        let previousMenuCardRendering = StatusItemController.menuCardRenderingEnabled
        let previousMenuRefresh = StatusItemController.menuRefreshEnabled
        StatusItemController.menuCardRenderingEnabled = false
        StatusItemController.setMenuRefreshEnabledForTesting(false)
        defer {
            StatusItemController.menuCardRenderingEnabled = previousMenuCardRendering
            StatusItemController.setMenuRefreshEnabledForTesting(previousMenuRefresh)
        }

        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true
        settings.selectedMenuProvider = .claude
        settings.mergedMenuLastSelectedWasOverview = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            let shouldEnable = provider == .zai || provider == .claude
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: shouldEnable)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let usage = ZaiUsageSnapshot(
            tokenLimit: nil,
            timeLimit: ZaiLimitEntry(
                type: .timeLimit,
                unit: .minutes,
                number: 1,
                usage: 100,
                currentValue: 50,
                remaining: 50,
                percentage: 50,
                usageDetails: [ZaiUsageDetail(modelCode: "glm-4.5", usage: 512)],
                nextResetTime: now.addingTimeInterval(3600)),
            planName: "Pro",
            updatedAt: now)
        store._setSnapshotForTesting(usage.toUsageSnapshot(), provider: .zai)

        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let menu = controller.makeMenu()
        controller.menuWillOpen(menu)

        let zaiRow = try #require(menu.items.first {
            ($0.representedObject as? String) == "overviewRow-zai"
        })
        let submenu = try #require(zaiRow.submenu)
        #expect(controller.isHostedSubviewMenu(submenu))

        // Hovering the row is what AppKit does before it opens the submenu; the controller
        // hydrates lazily via menuWillOpen on the submenu itself (mirrors the other hosted
        // chart submenus, e.g. cost history).
        controller.menuWillOpen(submenu)

        // Hydration replaces the single lazy placeholder item with the full detail screen:
        // header/usage card content plus actionable sections (status page, refresh, etc.).
        #expect(submenu.items.count > 1)
        #expect(submenu.items.contains { $0.representedObject as? String == "menuCard" } ||
            submenu.items.contains { $0.representedObject as? String == "menuCardUsage" } ||
            submenu.items.contains { $0.representedObject as? String == "menuCardHeader" })

        // The Overview selection state itself never changes just from hovering a submenu — no
        // click-through navigation exists, so the merged menu's Overview stays the "current" view.
        #expect(settings.mergedMenuLastSelectedWasOverview == true)
    }

    @Test
    func `overview submenu hydration is reachable through appendOverviewProviderDetailItems`() throws {
        self.disableMenuCardsForTesting()
        let settings = self.makeSettings()
        settings.statusChecksEnabled = false
        settings.refreshFrequency = .manual
        settings.mergeIcons = true

        let registry = ProviderRegistry.shared
        for provider in UsageProvider.allCases {
            guard let metadata = registry.metadata[provider] else { continue }
            settings.setProviderEnabled(provider: provider, metadata: metadata, enabled: provider == .codex)
        }

        let fetcher = UsageFetcher()
        let store = UsageStore(fetcher: fetcher, browserDetection: BrowserDetection(cacheTTL: 0), settings: settings)
        let controller = StatusItemController(
            store: store,
            settings: settings,
            account: fetcher.loadAccountInfo(),
            updater: DisabledUpdaterController(),
            preferencesSelection: PreferencesSelection(),
            statusBar: self.makeStatusBarForTesting())
        defer { controller.releaseStatusItemsForTesting() }

        let submenu = NSMenu()
        submenu.autoenablesItems = false
        _ = controller.appendOverviewProviderDetailItems(to: submenu, provider: .codex, width: 310)
        #expect(!submenu.items.isEmpty)
    }
}
