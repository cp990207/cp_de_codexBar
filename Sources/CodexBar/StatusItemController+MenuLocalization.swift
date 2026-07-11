import CodexBarCore

extension StatusItemController {
    func menuLocalizationSignature() -> String {
        [
            codexBarLocalizationSignature(),
            self.settings.hidePersonalInfo ? "hide-personal-info" : "show-personal-info",
            L("Overview"),
            L("Cost"),
        ].joined(separator: "|")
    }

    /// Records the localization signature the menu was just rebuilt with, so later settings-change
    /// checks (`handleSettingsChange`) can detect an app-language change and force a full rebuild.
    func rememberMenuLocalizationSignature() {
        self.lastMenuLocalizationSignature = self.menuLocalizationSignature()
    }
}
