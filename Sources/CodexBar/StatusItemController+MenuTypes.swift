import AppKit
import CodexBarCore
import SwiftUI

extension ProviderSwitcherSelection {
    var provider: UsageProvider? {
        switch self {
        case .overview:
            nil
        case let .provider(provider):
            provider
        }
    }
}

/// Overview row: brand icon + provider name header, hovered to reveal the provider's full detail
/// as a native submenu. Balance/currency metrics (DeepSeek, Mistral, etc.) render as trailing text
/// on the header line; quota metrics (Claude/Codex 5h, 7d, ...) each get a compact progress-bar
/// line below the header instead of a squeezed one-line summary.
struct OverviewMenuCardRowView: View {
    let model: UsageMenuCardView.Model
    let width: CGFloat
    @Environment(\.menuItemHighlighted) private var isHighlighted

    /// Metrics with meaningful `statusText` (balances/unlimited plans) render inline on the
    /// header row instead of getting their own progress-bar line.
    private var statusMetrics: [UsageMenuCardView.Model.Metric] {
        self.model.metrics.filter { metric in
            guard let status = metric.statusText?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return false
            }
            return !status.isEmpty
        }
    }

    /// Metrics without a status string get a compact progress-bar row (quota providers).
    private var progressMetrics: [UsageMenuCardView.Model.Metric] {
        self.model.metrics.filter { metric in
            let status = metric.statusText?.trimmingCharacters(in: .whitespacesAndNewlines)
            return status == nil || status?.isEmpty == true
        }
    }

    private var headerTrailingText: String? {
        guard self.model.metrics.isEmpty || !self.statusMetrics.isEmpty else { return nil }
        if !self.statusMetrics.isEmpty {
            return self.statusMetrics
                .map { metric in "\(metric.title) \(metric.statusText ?? "")" }
                .joined(separator: " · ")
        }
        // No metrics at all: fall back to the existing priority chain (credits → spend → subtitle).
        guard self.model.metrics.isEmpty else { return nil }
        return Self.fallbackSummaryText(for: self.model)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                if let brand = ProviderBrandIcon.image(for: self.model.provider) {
                    Image(nsImage: brand)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                        .accessibilityHidden(true)
                }
                Text(self.model.providerName)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(self.isHighlighted))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let headerTrailingText {
                    Text(headerTrailingText)
                        .font(.callout)
                        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            ForEach(self.progressMetrics) { metric in
                OverviewMenuCardMetricRow(metric: metric, progressColor: self.model.progressColor)
            }
        }
        .padding(.horizontal, UsageMenuCardLayout.horizontalPadding)
        .padding(.vertical, 6)
        .frame(width: self.width, alignment: .leading)
    }

    /// Priority: credits balance → provider spend line → subtitle fallback. Only used when the
    /// model has no metrics at all.
    static func fallbackSummaryText(for model: UsageMenuCardView.Model) -> String {
        if let credits = model.creditsText, !credits.isEmpty {
            return credits
        }
        if let providerCost = model.providerCost {
            return providerCost.spendLine
        }
        return model.subtitleText
    }
}

/// Compact progress-bar line for one quota metric inside an Overview row: a small label, a slim
/// bar, and the percent label — deliberately thinner than the detail card's `MetricRow` and
/// without pace stripes/markers to keep the Overview list dense.
private struct OverviewMenuCardMetricRow: View {
    let metric: UsageMenuCardView.Model.Metric
    let progressColor: Color
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Text(self.metric.title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .frame(minWidth: 22, alignment: .leading)
            UsageProgressBar(
                percent: self.metric.percent,
                tint: self.progressColor,
                accessibilityLabel: self.metric.percentStyle.accessibilityLabel)
                .frame(height: 4)
            Text(self.metric.percentLabel)
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

struct OpenAIWebMenuItems {
    let hasUsageBreakdown: Bool
    let hasCreditsHistory: Bool
    let hasCostHistory: Bool
    let canShowBuyCredits: Bool
}

struct TokenAccountMenuDisplay: Equatable {
    let provider: UsageProvider
    let accounts: [ProviderTokenAccount]
    let snapshots: [TokenAccountUsageSnapshot]
    let activeIndex: Int
    let layout: MultiAccountMenuLayout

    var showAll: Bool {
        self.layout == .stacked
    }

    var showSwitcher: Bool {
        self.layout == .segmented
    }

    static func == (lhs: TokenAccountMenuDisplay, rhs: TokenAccountMenuDisplay) -> Bool {
        lhs.provider == rhs.provider &&
            lhs.accountIdentity == rhs.accountIdentity &&
            lhs.activeIndex == rhs.activeIndex &&
            lhs.layout == rhs.layout &&
            lhs.snapshotIdentity == rhs.snapshotIdentity
    }

    private var accountIdentity: [AccountIdentity] {
        self.accounts.map { account in
            AccountIdentity(
                id: account.id,
                label: account.label,
                externalIdentifier: account.externalIdentifier,
                usageScope: account.usageScope,
                organizationID: account.organizationID,
                workspaceID: account.workspaceID)
        }
    }

    private var snapshotIdentity: [SnapshotIdentity] {
        self.snapshots.map { snapshot in
            SnapshotIdentity(
                id: snapshot.id,
                hasSnapshot: snapshot.snapshot != nil,
                error: snapshot.error,
                sourceLabel: snapshot.sourceLabel)
        }
    }

    private struct AccountIdentity: Equatable {
        let id: UUID
        let label: String
        let externalIdentifier: String?
        let usageScope: String?
        let organizationID: String?
        let workspaceID: String?
    }

    private struct SnapshotIdentity: Equatable {
        let id: UUID
        let hasSnapshot: Bool
        let error: String?
        let sourceLabel: String?
    }
}

struct CodexAccountMenuDisplay: Equatable {
    let accounts: [CodexVisibleAccount]
    let snapshots: [CodexAccountUsageSnapshot]
    let activeVisibleAccountID: String?
    let layout: MultiAccountMenuLayout

    var showAll: Bool {
        self.layout == .stacked
    }

    var showSwitcher: Bool {
        self.layout == .segmented
    }

    var workspaceSections: [CodexAccountWorkspaceSection] {
        self.accounts.codexWorkspaceSections()
    }

    var showsWorkspaceGroups: Bool {
        Set(self.workspaceSections.map(\.title)).count > 1
    }

    static func == (lhs: CodexAccountMenuDisplay, rhs: CodexAccountMenuDisplay) -> Bool {
        lhs.accounts == rhs.accounts &&
            lhs.activeVisibleAccountID == rhs.activeVisibleAccountID &&
            lhs.layout == rhs.layout &&
            lhs.snapshotIdentity == rhs.snapshotIdentity
    }

    private var snapshotIdentity: [SnapshotIdentity] {
        self.snapshots.map { snapshot in
            SnapshotIdentity(
                id: snapshot.id,
                hasSnapshot: snapshot.snapshot != nil,
                error: snapshot.error,
                sourceLabel: snapshot.sourceLabel)
        }
    }

    private struct SnapshotIdentity: Equatable {
        let id: String
        let hasSnapshot: Bool
        let error: String?
        let sourceLabel: String?
    }
}
