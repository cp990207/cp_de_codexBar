import CodexBarCore
import Foundation
import ServiceManagement

extension SettingsStore {
    func noteBackgroundWorkSettingsChanged() {
        self.backgroundWorkSettingsRevision &+= 1
    }

    var refreshFrequency: RefreshFrequency {
        get { self.defaultsState.refreshFrequency }
        set {
            self.defaultsState.refreshFrequency = newValue
            self.userDefaults.set(newValue.rawValue, forKey: "refreshFrequency")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    /// When enabled, keeping the menu open through its short refresh delay fetches usage for every
    /// enabled provider. The periodic refresh clock remains unchanged. See `scheduleOpenMenuRefresh`.
    var refreshAllProvidersOnMenuOpen: Bool {
        get { self.defaultsState.refreshAllProvidersOnMenuOpen }
        set {
            self.defaultsState.refreshAllProvidersOnMenuOpen = newValue
            self.userDefaults.set(newValue, forKey: "refreshAllProvidersOnMenuOpen")
        }
    }

    var launchAtLogin: Bool {
        get { self.defaultsState.launchAtLogin }
        set {
            self.defaultsState.launchAtLogin = newValue
            self.userDefaults.set(newValue, forKey: "launchAtLogin")
            LaunchAtLoginManager.setEnabled(newValue)
        }
    }

    var debugMenuEnabled: Bool {
        get { self.defaultsState.debugMenuEnabled }
        set {
            self.defaultsState.debugMenuEnabled = newValue
            self.userDefaults.set(newValue, forKey: "debugMenuEnabled")
        }
    }

    var debugDisableKeychainAccess: Bool {
        get { self.defaultsState.debugDisableKeychainAccess }
        set {
            self.defaultsState.debugDisableKeychainAccess = newValue
            self.userDefaults.set(newValue, forKey: "debugDisableKeychainAccess")
            if Self.shouldBridgeSharedDefaults(for: self.userDefaults) {
                Self.sharedDefaults?.set(newValue, forKey: "debugDisableKeychainAccess")
            }
            KeychainAccessGate.isDisabled = newValue
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var debugFileLoggingEnabled: Bool {
        get { self.defaultsState.debugFileLoggingEnabled }
        set {
            self.defaultsState.debugFileLoggingEnabled = newValue
            self.userDefaults.set(newValue, forKey: "debugFileLoggingEnabled")
            CodexBarLog.setFileLoggingEnabled(newValue)
        }
    }

    var debugLogLevel: CodexBarLog.Level {
        get {
            let raw = self.defaultsState.debugLogLevelRaw
            return CodexBarLog.parseLevel(raw) ?? .verbose
        }
        set {
            self.defaultsState.debugLogLevelRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "debugLogLevel")
            CodexBarLog.setLogLevel(newValue)
        }
    }

    var debugKeepCLISessionsAlive: Bool {
        get { self.defaultsState.debugKeepCLISessionsAlive }
        set {
            self.defaultsState.debugKeepCLISessionsAlive = newValue
            self.userDefaults.set(newValue, forKey: "debugKeepCLISessionsAlive")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var isVerboseLoggingEnabled: Bool {
        self.debugLogLevel.rank <= CodexBarLog.Level.verbose.rank
    }

    private var debugLoadingPatternRaw: String? {
        get { self.defaultsState.debugLoadingPatternRaw }
        set {
            self.defaultsState.debugLoadingPatternRaw = newValue
            if let raw = newValue {
                self.userDefaults.set(raw, forKey: "debugLoadingPattern")
            } else {
                self.userDefaults.removeObject(forKey: "debugLoadingPattern")
            }
        }
    }

    var statusChecksEnabled: Bool {
        get { self.defaultsState.statusChecksEnabled }
        set {
            self.defaultsState.statusChecksEnabled = newValue
            self.userDefaults.set(newValue, forKey: "statusChecksEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var sessionQuotaNotificationsEnabled: Bool {
        get { self.defaultsState.sessionQuotaNotificationsEnabled }
        set {
            self.defaultsState.sessionQuotaNotificationsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "sessionQuotaNotificationsEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var quotaWarningNotificationsEnabled: Bool {
        get { self.defaultsState.quotaWarningNotificationsEnabled }
        set {
            self.defaultsState.quotaWarningNotificationsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "quotaWarningNotificationsEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var predictivePaceWarningNotificationsEnabled: Bool {
        get { self.defaultsState.predictivePaceWarningNotificationsEnabled }
        set {
            guard self.defaultsState.predictivePaceWarningNotificationsEnabled != newValue else { return }
            self.defaultsState.predictivePaceWarningNotificationsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "predictivePaceWarningNotificationsEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var quotaWarningThresholds: [Int] {
        get { QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningThresholdsRaw) }
        set {
            let sanitized = QuotaWarningThresholds.sanitized(newValue)
            guard QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningThresholdsRaw) != sanitized
                || QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningSessionThresholdsRaw) != sanitized
                || QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningWeeklyThresholdsRaw) != sanitized
            else {
                return
            }
            self.defaultsState.quotaWarningThresholdsRaw = sanitized
            self.defaultsState.quotaWarningSessionThresholdsRaw = sanitized
            self.defaultsState.quotaWarningWeeklyThresholdsRaw = sanitized
            self.userDefaults.set(sanitized, forKey: "quotaWarningThresholds")
            self.userDefaults.set(sanitized, forKey: "quotaWarningSessionThresholds")
            self.userDefaults.set(sanitized, forKey: "quotaWarningWeeklyThresholds")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    func quotaWarningThresholds(_ window: QuotaWarningWindow) -> [Int] {
        switch window {
        case .session:
            QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningSessionThresholdsRaw)
        case .weekly:
            QuotaWarningThresholds.sanitized(self.defaultsState.quotaWarningWeeklyThresholdsRaw)
        }
    }

    func setQuotaWarningThresholds(_ window: QuotaWarningWindow, thresholds: [Int]) {
        let sanitized = QuotaWarningThresholds.sanitized(thresholds)
        guard self.quotaWarningThresholds(window) != sanitized else { return }
        switch window {
        case .session:
            self.defaultsState.quotaWarningSessionThresholdsRaw = sanitized
            self.userDefaults.set(sanitized, forKey: "quotaWarningSessionThresholds")
        case .weekly:
            self.defaultsState.quotaWarningWeeklyThresholdsRaw = sanitized
            self.userDefaults.set(sanitized, forKey: "quotaWarningWeeklyThresholds")
        }
        self.noteBackgroundWorkSettingsChanged()
    }

    func quotaWarningWindowEnabled(_ window: QuotaWarningWindow) -> Bool {
        switch window {
        case .session:
            self.defaultsState.quotaWarningSessionEnabled
        case .weekly:
            self.defaultsState.quotaWarningWeeklyEnabled
        }
    }

    func setQuotaWarningWindowEnabled(_ window: QuotaWarningWindow, enabled: Bool) {
        switch window {
        case .session:
            self.defaultsState.quotaWarningSessionEnabled = enabled
            self.userDefaults.set(enabled, forKey: "quotaWarningSessionEnabled")
        case .weekly:
            self.defaultsState.quotaWarningWeeklyEnabled = enabled
            self.userDefaults.set(enabled, forKey: "quotaWarningWeeklyEnabled")
        }
        self.noteBackgroundWorkSettingsChanged()
    }

    var quotaWarningSoundEnabled: Bool {
        get { self.defaultsState.quotaWarningSoundEnabled }
        set {
            self.defaultsState.quotaWarningSoundEnabled = newValue
            self.userDefaults.set(newValue, forKey: "quotaWarningSoundEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var quotaWarningOnScreenAlertEnabled: Bool {
        get { self.defaultsState.quotaWarningOnScreenAlertEnabled }
        set {
            self.defaultsState.quotaWarningOnScreenAlertEnabled = newValue
            self.userDefaults.set(newValue, forKey: "quotaWarningOnScreenAlertEnabled")
        }
    }

    var quotaWarningMarkersVisible: Bool {
        get { self.defaultsState.quotaWarningMarkersVisible }
        set {
            self.defaultsState.quotaWarningMarkersVisible = newValue
            self.userDefaults.set(newValue, forKey: "quotaWarningMarkersVisible")
        }
    }

    var weeklyProgressWorkDays: Int? {
        get { self.defaultsState.weeklyProgressWorkDays }
        set {
            self.defaultsState.weeklyProgressWorkDays = newValue
            if let newValue {
                self.userDefaults.set(newValue, forKey: "weeklyProgressWorkDays")
            } else {
                self.userDefaults.removeObject(forKey: "weeklyProgressWorkDays")
            }
        }
    }

    var usageBarsShowUsed: Bool {
        get { self.defaultsState.usageBarsShowUsed }
        set {
            self.defaultsState.usageBarsShowUsed = newValue
            self.userDefaults.set(newValue, forKey: "usageBarsShowUsed")
        }
    }

    var resetTimesShowAbsolute: Bool {
        get { self.defaultsState.resetTimesShowAbsolute }
        set {
            self.defaultsState.resetTimesShowAbsolute = newValue
            self.userDefaults.set(newValue, forKey: "resetTimesShowAbsolute")
        }
    }

    var providerChangelogLinksEnabled: Bool {
        get { self.defaultsState.providerChangelogLinksEnabled }
        set {
            self.defaultsState.providerChangelogLinksEnabled = newValue
            self.userDefaults.set(newValue, forKey: "providerChangelogLinksEnabled")
        }
    }

    var menuBarShowsBrandIconWithPercent: Bool {
        get { self.defaultsState.menuBarShowsBrandIconWithPercent }
        set {
            self.defaultsState.menuBarShowsBrandIconWithPercent = newValue
            self.userDefaults.set(newValue, forKey: "menuBarShowsBrandIconWithPercent")
        }
    }

    var menuBarHidesCritters: Bool {
        get { self.defaultsState.menuBarHidesCritters }
        set {
            self.defaultsState.menuBarHidesCritters = newValue
            self.userDefaults.set(newValue, forKey: "menuBarHidesCritters")
        }
    }

    private var menuBarDisplayModeRaw: String? {
        get { self.defaultsState.menuBarDisplayModeRaw }
        set {
            self.defaultsState.menuBarDisplayModeRaw = newValue
            if let raw = newValue {
                self.userDefaults.set(raw, forKey: "menuBarDisplayMode")
            } else {
                self.userDefaults.removeObject(forKey: "menuBarDisplayMode")
            }
        }
    }

    var menuBarDisplayMode: MenuBarDisplayMode {
        get { MenuBarDisplayMode(rawValue: self.menuBarDisplayModeRaw ?? "") ?? .percent }
        set { self.menuBarDisplayModeRaw = newValue.rawValue }
    }

    var menuBarShowsResetTimeWhenExhausted: Bool {
        get { self.defaultsState.menuBarShowsResetTimeWhenExhausted }
        set {
            self.defaultsState.menuBarShowsResetTimeWhenExhausted = newValue
            self.userDefaults.set(newValue, forKey: "menuBarShowsResetTimeWhenExhausted")
        }
    }

    private var kiroMenuBarDisplayModeRaw: String? {
        get { self.defaultsState.kiroMenuBarDisplayModeRaw }
        set {
            self.defaultsState.kiroMenuBarDisplayModeRaw = newValue
            if let raw = newValue {
                self.userDefaults.set(raw, forKey: "kiroMenuBarDisplayMode")
            } else {
                self.userDefaults.removeObject(forKey: "kiroMenuBarDisplayMode")
            }
        }
    }

    var kiroMenuBarDisplayMode: KiroMenuBarDisplayMode {
        get { KiroMenuBarDisplayMode(rawValue: self.kiroMenuBarDisplayModeRaw ?? "") ?? .automatic }
        set { self.kiroMenuBarDisplayModeRaw = newValue.rawValue }
    }

    var multiAccountMenuLayout: MultiAccountMenuLayout {
        get { MultiAccountMenuLayout(rawValue: self.defaultsState.multiAccountMenuLayoutRaw) ?? .segmented }
        set {
            self.defaultsState.multiAccountMenuLayoutRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "multiAccountMenuLayout")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var showAllTokenAccountsInMenu: Bool {
        get { self.multiAccountMenuLayout == .stacked }
        set { self.multiAccountMenuLayout = newValue ? .stacked : .segmented }
    }

    var historicalTrackingEnabled: Bool {
        get { self.defaultsState.historicalTrackingEnabled }
        set {
            self.defaultsState.historicalTrackingEnabled = newValue
            self.userDefaults.set(newValue, forKey: "historicalTrackingEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var menuBarMetricPreferencesRaw: [String: String] {
        get { self.defaultsState.menuBarMetricPreferencesRaw }
        set {
            self.defaultsState.menuBarMetricPreferencesRaw = newValue
            self.userDefaults.set(newValue, forKey: "menuBarMetricPreferences")
        }
    }

    var copilotIconSecondaryWindowIDRaw: String {
        get { self.defaultsState.copilotIconSecondaryWindowIDRaw }
        set {
            self.defaultsState.copilotIconSecondaryWindowIDRaw = newValue
            self.userDefaults.set(newValue, forKey: "copilotIconSecondaryWindowID")
        }
    }

    var costUsageEnabled: Bool {
        get { self.defaultsState.costUsageEnabled }
        set {
            self.defaultsState.costUsageEnabled = newValue
            self.userDefaults.set(newValue, forKey: "tokenCostUsageEnabled")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var costUsageHistoryDays: Int {
        get { self.defaultsState.costUsageHistoryDays }
        set {
            let clamped = max(1, min(365, newValue))
            self.defaultsState.costUsageHistoryDays = clamped
            self.userDefaults.set(clamped, forKey: "tokenCostUsageHistoryDays")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var costComparisonPeriodsEnabled: Bool {
        get { self.defaultsState.costComparisonPeriodsEnabled }
        set {
            self.defaultsState.costComparisonPeriodsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "costComparisonPeriodsEnabled")
        }
    }

    var costSummaryDisplayStyleRaw: String {
        get { self.defaultsState.costSummaryDisplayStyleRaw }
        set {
            self.defaultsState.costSummaryDisplayStyleRaw = newValue
            self.userDefaults.set(newValue, forKey: "costSummaryDisplayStyle")
        }
    }

    var costSummaryDisplayStyle: CostSummaryDisplayStyle {
        get { CostSummaryDisplayStyle(rawValue: self.costSummaryDisplayStyleRaw) ?? .both }
        set { self.costSummaryDisplayStyleRaw = newValue.rawValue }
    }

    var hidePersonalInfo: Bool {
        get { self.defaultsState.hidePersonalInfo }
        set {
            self.defaultsState.hidePersonalInfo = newValue
            self.userDefaults.set(newValue, forKey: "hidePersonalInfo")
        }
    }

    var randomBlinkEnabled: Bool {
        get { self.defaultsState.randomBlinkEnabled }
        set {
            self.defaultsState.randomBlinkEnabled = newValue
            self.userDefaults.set(newValue, forKey: "randomBlinkEnabled")
        }
    }

    var confettiOnSessionLimitResetsEnabled: Bool {
        get { self.defaultsState.confettiOnSessionLimitResetsEnabled }
        set {
            self.defaultsState.confettiOnSessionLimitResetsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "confettiOnSessionLimitResetsEnabled")
        }
    }

    var confettiOnWeeklyLimitResetsEnabled: Bool {
        get { self.defaultsState.confettiOnWeeklyLimitResetsEnabled }
        set {
            self.defaultsState.confettiOnWeeklyLimitResetsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "confettiOnWeeklyLimitResetsEnabled")
        }
    }

    var menuBarShowsHighestUsage: Bool {
        get { self.defaultsState.menuBarShowsHighestUsage }
        set {
            self.defaultsState.menuBarShowsHighestUsage = newValue
            self.userDefaults.set(newValue, forKey: "menuBarShowsHighestUsage")
        }
    }

    var claudeOAuthKeychainPromptMode: ClaudeOAuthKeychainPromptMode {
        get {
            let raw = self.defaultsState.claudeOAuthKeychainPromptModeRaw
            return ClaudeOAuthKeychainPromptMode(rawValue: raw ?? "") ?? .onlyOnUserAction
        }
        set {
            self.defaultsState.claudeOAuthKeychainPromptModeRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "claudeOAuthKeychainPromptMode")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var claudeOAuthKeychainReadStrategy: ClaudeOAuthKeychainReadStrategy {
        get {
            guard let raw = self.defaultsState.claudeOAuthKeychainReadStrategyRaw else {
                return .securityFramework
            }
            let strategy = ClaudeOAuthKeychainReadStrategy(rawValue: raw) ?? .securityFramework
            return strategy == .securityCLIExperimental ? .securityFramework : strategy
        }
        set {
            self.defaultsState.claudeOAuthKeychainReadStrategyRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "claudeOAuthKeychainReadStrategy")
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var claudeOAuthPromptFreeCredentialsEnabled: Bool {
        get { self.claudeOAuthKeychainPromptMode == .never }
        set {
            self.claudeOAuthKeychainReadStrategy = .securityFramework
            if newValue {
                self.claudeOAuthKeychainPromptMode = .never
            } else if self.claudeOAuthKeychainPromptMode == .never {
                self.claudeOAuthKeychainPromptMode = .onlyOnUserAction
            }
        }
    }

    var claudeWebExtrasEnabled: Bool {
        get { self.claudeWebExtrasEnabledRaw }
        set { self.claudeWebExtrasEnabledRaw = newValue }
    }

    var copilotBudgetExtrasEnabled: Bool {
        get { self.defaultsState.copilotBudgetExtrasEnabled }
        set {
            self.defaultsState.copilotBudgetExtrasEnabled = newValue
            self.userDefaults.set(newValue, forKey: "copilotBudgetExtrasEnabled")
            CodexBarLog.logger(LogCategories.settings).info(
                "Copilot budget extras updated",
                metadata: ["enabled": newValue ? "1" : "0"])
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    private var claudeWebExtrasEnabledRaw: Bool {
        get { self.defaultsState.claudeWebExtrasEnabledRaw }
        set {
            self.defaultsState.claudeWebExtrasEnabledRaw = newValue
            self.userDefaults.set(newValue, forKey: "claudeWebExtrasEnabled")
            CodexBarLog.logger(LogCategories.settings).info(
                "Claude web extras updated",
                metadata: ["enabled": newValue ? "1" : "0"])
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var showOptionalCreditsAndExtraUsage: Bool {
        get { self.defaultsState.showOptionalCreditsAndExtraUsage }
        set {
            self.defaultsState.showOptionalCreditsAndExtraUsage = newValue
            self.userDefaults.set(newValue, forKey: "showOptionalCreditsAndExtraUsage")
            // This flag also controls ProviderFetchContext.includeOptionalUsage, so it is not display-only.
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var codexSparkUsageVisible: Bool {
        get { self.defaultsState.codexSparkUsageVisible }
        set {
            self.defaultsState.codexSparkUsageVisible = newValue
            self.userDefaults.set(newValue, forKey: "codexSparkUsageVisible")
        }
    }

    var openAIWebAccessEnabled: Bool {
        get { self.defaultsState.openAIWebAccessEnabled }
        set {
            self.defaultsState.openAIWebAccessEnabled = newValue
            self.userDefaults.set(newValue, forKey: "openAIWebAccessEnabled")
            CodexBarLog.logger(LogCategories.settings).info(
                "OpenAI web access updated",
                metadata: ["enabled": newValue ? "1" : "0"])
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var openAIWebBatterySaverEnabled: Bool {
        get { self.defaultsState.openAIWebBatterySaverEnabled }
        set {
            self.defaultsState.openAIWebBatterySaverEnabled = newValue
            self.userDefaults.set(newValue, forKey: "openAIWebBatterySaverEnabled")
            CodexBarLog.logger(LogCategories.settings).info(
                "OpenAI web battery saver updated",
                metadata: ["enabled": newValue ? "1" : "0"])
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var providerStorageFootprintsEnabled: Bool {
        get { self.defaultsState.providerStorageFootprintsEnabled }
        set {
            self.defaultsState.providerStorageFootprintsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "providerStorageFootprintsEnabled")
            CodexBarLog.logger(LogCategories.settings).info(
                "Provider storage footprints updated",
                metadata: ["enabled": newValue ? "1" : "0"])
            self.noteBackgroundWorkSettingsChanged()
        }
    }

    var jetbrainsIDEBasePath: String {
        get { self.defaultsState.jetbrainsIDEBasePath }
        set {
            self.defaultsState.jetbrainsIDEBasePath = newValue
            self.userDefaults.set(newValue, forKey: "jetbrainsIDEBasePath")
        }
    }

    var mergeIcons: Bool {
        get { self.defaultsState.mergeIcons }
        set {
            self.defaultsState.mergeIcons = newValue
            self.userDefaults.set(newValue, forKey: "mergeIcons")
        }
    }

    var mergedMenuLastSelectedWasOverview: Bool {
        get { self.mergedMenuLastSelectedWasOverviewStorage }
        set {
            self.mergedMenuLastSelectedWasOverviewStorage = newValue
            self.userDefaults.set(newValue, forKey: "mergedMenuLastSelectedWasOverview")
        }
    }

    private var selectedMenuProviderRaw: String? {
        get { self.selectedMenuProviderRawStorage }
        set {
            self.selectedMenuProviderRawStorage = newValue
            if let raw = newValue {
                self.userDefaults.set(raw, forKey: "selectedMenuProvider")
            } else {
                self.userDefaults.removeObject(forKey: "selectedMenuProvider")
            }
        }
    }

    var selectedMenuProvider: UsageProvider? {
        get { self.selectedMenuProviderRaw.flatMap(UsageProvider.init(rawValue:)) }
        set {
            self.selectedMenuProviderRaw = newValue?.rawValue
        }
    }

    /// The full set of providers shown in the merged Overview list: all active providers, deduped
    /// and kept in their configured order. There is no cap and no per-provider selection — the
    /// Overview always mirrors every enabled provider and relies on native menu scrolling for overflow.
    func resolvedMergedOverviewProviders(activeProviders: [UsageProvider]) -> [UsageProvider] {
        Self.normalizeProviders(activeProviders)
    }

    var providerDetectionCompleted: Bool {
        get { self.defaultsState.providerDetectionCompleted }
        set {
            self.defaultsState.providerDetectionCompleted = newValue
            self.userDefaults.set(newValue, forKey: "providerDetectionCompleted")
        }
    }

    /// Whether the Providers settings pane displays providers sorted alphabetically (enabled on
    /// top). Defaults to `false`. Purely a display preference — it never rewrites the stored manual
    /// order, so turning it on sorts the display without losing the user's hand-arranged sequence.
    var providersSortedAlphabetically: Bool {
        get { self.defaultsState.providersSortedAlphabetically }
        set {
            self.defaultsState.providersSortedAlphabetically = newValue
            self.userDefaults.set(newValue, forKey: "providersSortedAlphabetically")
        }
    }

    var appLanguage: String {
        get { self.defaultsState.appLanguageRaw ?? "" }
        set {
            let stored = newValue.isEmpty ? nil : newValue
            self.defaultsState.appLanguageRaw = stored
            if let stored {
                self.userDefaults.set(stored, forKey: "appLanguage")
                if self.userDefaults !== UserDefaults.standard {
                    UserDefaults.standard.set(stored, forKey: "appLanguage")
                }
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                self.userDefaults.removeObject(forKey: "appLanguage")
                if self.userDefaults !== UserDefaults.standard {
                    UserDefaults.standard.removeObject(forKey: "appLanguage")
                }
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            }
            resetCodexBarLocalizationCache()
        }
    }

    var debugLoadingPattern: LoadingPattern? {
        get { self.debugLoadingPatternRaw.flatMap(LoadingPattern.init(rawValue:)) }
        set { self.debugLoadingPatternRaw = newValue?.rawValue }
    }

    var terminalApp: TerminalApp {
        get { TerminalApp(rawValue: self.defaultsState.terminalAppRaw ?? "") ?? .terminal }
        set {
            self.defaultsState.terminalAppRaw = newValue.rawValue
            self.userDefaults.set(newValue.rawValue, forKey: "terminalApp")
        }
    }

    var agentSessionsEnabled: Bool {
        get { self.defaultsState.agentSessionsEnabled }
        set {
            self.defaultsState.agentSessionsEnabled = newValue
            self.userDefaults.set(newValue, forKey: "agentSessionsEnabled")
        }
    }

    var agentSessionsManualHosts: String {
        get { self.defaultsState.agentSessionsManualHosts }
        set {
            self.defaultsState.agentSessionsManualHosts = newValue
            self.userDefaults.set(newValue, forKey: "agentSessionsManualHosts")
        }
    }
}

extension SettingsStore {
    private static func normalizeProviders(_ providers: [UsageProvider]) -> [UsageProvider] {
        var seen: Set<UsageProvider> = []
        var normalized: [UsageProvider] = []
        for provider in providers where !seen.contains(provider) {
            seen.insert(provider)
            normalized.append(provider)
        }
        return normalized
    }
}
