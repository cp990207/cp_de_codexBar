import AppKit
import CodexBarCore

extension StatusItemController {
    func trimRebuildableCachesForMemoryPressure() -> MemoryPressureCacheTrimSummary {
        let summary = MemoryPressureCacheTrimSummary(
            menuCardHeights: self.menuCardHeightCache.count,
            menuWidths: self.measuredStandardMenuWidthCache.count,
            recycledMenuCardViews: self.menuCardViewRecyclePool.count)

        self.menuCardHeightCache.removeAll(keepingCapacity: false)
        self.measuredStandardMenuWidthCache.removeAll(keepingCapacity: false)
        self.menuCardViewRecyclePool.removeAll(keepingCapacity: false)

        return summary
    }

    #if DEBUG
    func seedRebuildableCachesForMemoryPressureProof() {
        self.menuCardHeightCache[
            MenuCardHeightCacheKey(
                id: "debug-memory-pressure-card",
                scope: UsageProvider.codex.rawValue,
                width: 30000,
                textScale: Self.menuCardHeightTextScaleToken(),
                fingerprint: "debug-memory-pressure"),
        ] = 44
        self.measuredStandardMenuWidthCache["debug-memory-pressure-width"] = 300
        self.menuCardViewRecyclePool["debug-memory-pressure-card"] = NSView()
    }
    #endif
}
