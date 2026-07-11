import CodexBarCore

/// Identifies which top-level content a merged menu is showing. Overview is now the only
/// top-level state for the merged menu (icons merged, >1 provider); `.provider` remains used
/// for the single-provider (non-merged) menu path and by `resolvedMenuProvider`/menu-bar-icon
/// selection bookkeeping.
enum ProviderSwitcherSelection: Hashable {
    case overview
    case provider(UsageProvider)
}
