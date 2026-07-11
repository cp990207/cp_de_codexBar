import AppKit
import CodexBarCore

final class TokenAccountSwitcherView: NSView {
    private let accounts: [ProviderTokenAccount]
    private let onSelect: (Int) -> Task<Void, Never>?
    private var selectedIndex: Int
    private var buttons: [NSButton] = []
    private let preferredSize: NSSize
    private let rowSpacing: CGFloat = 4
    private let rowHeight: CGFloat = 26
    private let selectedBackground = NSColor.controlAccentColor.cgColor
    private let unselectedBackground = NSColor.clear.cgColor
    private let selectedTextColor = NSColor.white
    private let unselectedTextColor = NSColor.secondaryLabelColor

    init(
        accounts: [ProviderTokenAccount],
        selectedIndex: Int,
        width: CGFloat,
        onSelect: @escaping (Int) -> Task<Void, Never>?)
    {
        self.accounts = accounts
        self.onSelect = onSelect
        self.selectedIndex = min(max(selectedIndex, 0), max(0, accounts.count - 1))
        let useTwoRows = accounts.count > 3
        let rows = useTwoRows ? 2 : 1
        let height = self.rowHeight * CGFloat(rows) + (useTwoRows ? self.rowSpacing : 0)
        self.preferredSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.wantsLayer = true
        self.buildButtons(useTwoRows: useTwoRows)
        self.updateButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    override var fittingSize: NSSize {
        self.preferredSize
    }

    private func buildButtons(useTwoRows: Bool) {
        let perRow = useTwoRows ? Int(ceil(Double(self.accounts.count) / 2.0)) : self.accounts.count
        let rows: [[ProviderTokenAccount]] = {
            if !useTwoRows { return [self.accounts] }
            let first = Array(self.accounts.prefix(perRow))
            let second = Array(self.accounts.dropFirst(perRow))
            return [first, second]
        }()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        var globalIndex = 0
        for rowAccounts in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = self.rowSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            for account in rowAccounts {
                let button = PaddedToggleButton(
                    title: account.displayName,
                    target: self,
                    action: #selector(self.handleSelect))
                button.tag = globalIndex
                button.toolTip = account.displayName
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
                button.cell?.lineBreakMode = account.displayName.contains("@") ? .byTruncatingMiddle : .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                row.addArrangedSubview(button)
                self.buttons.append(button)
                globalIndex += 1
            }

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -6),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: self.rowHeight * CGFloat(rows.count) +
                (useTwoRows ? self.rowSpacing : 0)),
        ])
    }

    private func updateButtonStyles() {
        for (index, button) in self.buttons.enumerated() {
            let selected = index == self.selectedIndex
            button.state = selected ? .on : .off
            button.layer?.backgroundColor = selected ? self.selectedBackground : self.unselectedBackground
            button.contentTintColor = selected ? self.selectedTextColor : self.unselectedTextColor
        }
    }

    @objc private func handleSelect(_ sender: NSButton) {
        _ = self.select(index: sender.tag)
    }

    @discardableResult
    private func select(index: Int) -> Task<Void, Never>? {
        guard index >= 0, index < self.accounts.count else { return nil }
        self.selectedIndex = index
        self.updateButtonStyles()
        return self.onSelect(index)
    }

    #if DEBUG
    func _test_select(index: Int) -> Task<Void, Never>? {
        guard let button = self.buttons.first(where: { $0.tag == index }) else { return nil }
        return self.select(index: button.tag)
    }

    func _test_buttonTitles() -> [String] {
        self.buttons.map(\.title)
    }
    #endif
}

final class CodexAccountSwitcherView: NSView {
    private let accounts: [CodexVisibleAccount]
    private let onSelect: (CodexVisibleAccount) -> Void
    private var selectedAccountID: String
    private var pressedAccountID: String?
    private var buttons: [NSButton] = []
    private let preferredSize: NSSize
    private let rowSpacing: CGFloat = 4
    private let rowHeight: CGFloat = 26
    private let selectedBackground = NSColor.controlAccentColor.cgColor
    private let unselectedBackground = NSColor.clear.cgColor
    private let selectedTextColor = NSColor.white
    private let unselectedTextColor = NSColor.secondaryLabelColor
    private let buttonFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    private let buttonHorizontalPadding: CGFloat = 14
    private let buttonSideInset: CGFloat = 6

    init(
        accounts: [CodexVisibleAccount],
        selectedAccountID: String?,
        width: CGFloat,
        onSelect: @escaping (CodexVisibleAccount) -> Void)
    {
        self.accounts = accounts
        self.onSelect = onSelect
        self.selectedAccountID = selectedAccountID ?? accounts.first?.id ?? ""
        let useTwoRows = accounts.count > 3
        let rows = useTwoRows ? 2 : 1
        let height = self.rowHeight * CGFloat(rows) + (useTwoRows ? self.rowSpacing : 0)
        self.preferredSize = NSSize(width: width, height: height)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        self.wantsLayer = true
        self.buildButtons(useTwoRows: useTwoRows)
        self.updateButtonStyles()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        self.preferredSize
    }

    override var fittingSize: NSSize {
        self.preferredSize
    }

    private func buildButtons(useTwoRows: Bool) {
        let perRow = useTwoRows ? Int(ceil(Double(self.accounts.count) / 2.0)) : self.accounts.count
        let rows: [[CodexVisibleAccount]] = {
            if !useTwoRows { return [self.accounts] }
            let first = Array(self.accounts.prefix(perRow))
            let second = Array(self.accounts.dropFirst(perRow))
            return [first, second]
        }()
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = self.rowSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        for rowAccounts in rows {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.distribution = .fillEqually
            row.spacing = self.rowSpacing
            row.translatesAutoresizingMaskIntoConstraints = false

            let buttonWidth = self.buttonWidth(for: rowAccounts.count)
            for account in rowAccounts {
                let title = self.compactButtonTitle(for: account, buttonWidth: buttonWidth)
                let button = PaddedToggleButton(
                    title: title,
                    target: self,
                    action: #selector(self.handleSelect))
                button.identifier = NSUserInterfaceItemIdentifier(account.id)
                button.toolTip = account.menuDisplayName
                button.isBordered = false
                button.setButtonType(.toggle)
                button.controlSize = .small
                button.font = self.buttonFont
                button.cell?.lineBreakMode = .byTruncatingTail
                button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
                button.wantsLayer = true
                button.layer?.cornerRadius = 6
                row.addArrangedSubview(button)
                self.buttons.append(button)
            }

            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        self.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: self.buttonSideInset),
            stack.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -self.buttonSideInset),
            stack.topAnchor.constraint(equalTo: self.topAnchor),
            stack.bottomAnchor.constraint(equalTo: self.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: self.rowHeight * CGFloat(rows.count) +
                (useTwoRows ? self.rowSpacing : 0)),
        ])
    }

    private func buttonWidth(for count: Int) -> CGFloat {
        let contentWidth = self.bounds.width - (self.buttonSideInset * 2)
        let spacing = self.rowSpacing * CGFloat(max(0, count - 1))
        guard count > 0 else { return contentWidth }
        return max(44, floor((contentWidth - spacing) / CGFloat(count)))
    }

    private func compactButtonTitle(for account: CodexVisibleAccount, buttonWidth: CGFloat) -> String {
        let availableTextWidth = max(24, buttonWidth - self.buttonHorizontalPadding)
        if self.textWidth(account.menuDisplayName) <= availableTextWidth {
            return account.menuDisplayName
        }

        guard let workspace = account.menuWorkspaceLabel else {
            return self.truncateMiddle(account.email, toFit: availableTextWidth)
        }

        let separator = "|"
        let separatorWidth = self.textWidth(separator)
        let contentWidth = max(24, availableTextWidth - separatorWidth)
        let minimumEmailWidth = min(contentWidth * 0.45, max(18, contentWidth * 0.3))
        let minimumWorkspaceWidth = min(contentWidth * 0.4, max(18, contentWidth * 0.25))
        var emailWidth = max(minimumEmailWidth, contentWidth * 0.58)
        var workspaceWidth = max(minimumWorkspaceWidth, contentWidth - emailWidth)

        func makeTitle() -> String {
            let email = self.truncateMiddle(account.email, toFit: emailWidth)
            let workspace = self.truncateTail(workspace, toFit: workspaceWidth)
            return "\(email)\(separator)\(workspace)"
        }

        var title = makeTitle()
        var attempts = 0
        while self.textWidth(title) > availableTextWidth, attempts < 16 {
            let emailText = self.truncateMiddle(account.email, toFit: emailWidth)
            let workspaceText = self.truncateTail(workspace, toFit: workspaceWidth)
            let emailRenderedWidth = self.textWidth(emailText)
            let workspaceRenderedWidth = self.textWidth(workspaceText)

            if emailRenderedWidth >= workspaceRenderedWidth, emailWidth > minimumEmailWidth {
                emailWidth = max(minimumEmailWidth, emailWidth - 6)
            } else if workspaceWidth > minimumWorkspaceWidth {
                workspaceWidth = max(minimumWorkspaceWidth, workspaceWidth - 6)
            } else {
                break
            }

            title = makeTitle()
            attempts += 1
        }

        return title
    }

    private func truncateTail(_ text: String, toFit width: CGFloat) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if self.textWidth(trimmed) <= width {
            return trimmed
        }

        let ellipsis = "…"
        let ellipsisWidth = self.textWidth(ellipsis)
        guard ellipsisWidth < width else { return ellipsis }

        var candidate = ""
        for character in trimmed {
            let next = candidate + String(character)
            if self.textWidth(next + ellipsis) > width {
                break
            }
            candidate = next
        }

        if candidate.isEmpty {
            return ellipsis
        }
        return candidate + ellipsis
    }

    private func truncateMiddle(_ text: String, toFit width: CGFloat) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        if self.textWidth(trimmed) <= width {
            return trimmed
        }

        let ellipsis = "…"
        let ellipsisWidth = self.textWidth(ellipsis)
        guard ellipsisWidth < width else { return ellipsis }

        var prefix = ""
        var suffix = ""
        var prefixIndex = trimmed.startIndex
        var suffixIndex = trimmed.endIndex
        var best = ellipsis
        var takeSuffixNext = true

        while prefixIndex < suffixIndex {
            let nextPrefix: String
            let nextSuffix: String
            if takeSuffixNext {
                let previousIndex = trimmed.index(before: suffixIndex)
                nextPrefix = prefix
                nextSuffix = String(trimmed[previousIndex]) + suffix
                suffixIndex = previousIndex
            } else {
                nextPrefix = prefix + String(trimmed[prefixIndex])
                nextSuffix = suffix
                prefixIndex = trimmed.index(after: prefixIndex)
            }

            let candidate = nextPrefix + ellipsis + nextSuffix
            if self.textWidth(candidate) > width {
                break
            }

            prefix = nextPrefix
            suffix = nextSuffix
            best = candidate
            takeSuffixNext.toggle()
        }

        return best
    }

    private func textWidth(_ text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: self.buttonFont]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }

    private func updateButtonStyles() {
        for button in self.buttons {
            let selected = button.identifier?.rawValue == self.selectedAccountID
            button.state = selected ? .on : .off
            button.layer?.backgroundColor = selected ? self.selectedBackground : self.unselectedBackground
            button.contentTintColor = selected ? self.selectedTextColor : self.unselectedTextColor
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let descendant = super.hitTest(point)
        if descendant != nil, descendant !== self {
            self.toolTip = (descendant as? NSButton)?.toolTip
            return self
        }
        self.toolTip = nil
        return descendant
    }

    override func mouseDown(with event: NSEvent) {
        let location = self.convert(event.locationInWindow, from: nil)
        self.pressedAccountID = self.accountID(at: location)
    }

    override func mouseUp(with event: NSEvent) {
        defer { self.pressedAccountID = nil }
        guard let pressedAccountID = self.pressedAccountID else { return }
        let location = self.convert(event.locationInWindow, from: nil)
        guard let releasedAccountID = self.accountID(at: location),
              releasedAccountID == pressedAccountID,
              let account = self.accounts.first(where: { $0.id == pressedAccountID })
        else {
            return
        }
        self.applySelection(account)
    }

    private func accountID(at pointInSelf: NSPoint) -> String? {
        self.buttons.first(where: { self.convert($0.bounds, from: $0).contains(pointInSelf) })?.identifier?.rawValue
    }

    @objc private func handleSelect(_ sender: NSButton) {
        guard let accountID = sender.identifier?.rawValue,
              let account = self.accounts.first(where: { $0.id == accountID }) else { return }
        self.applySelection(account)
    }

    private func applySelection(_ account: CodexVisibleAccount) {
        self.selectedAccountID = account.id
        self.updateButtonStyles()
        self.onSelect(account)
    }

    #if DEBUG
    func _test_buttonTitles() -> [String] {
        self.buttons.map(\.title)
    }

    func _test_buttonToolTips() -> [String?] {
        self.buttons.map(\.toolTip)
    }

    func _test_selectAccount(id: String) {
        guard let account = self.accounts.first(where: { $0.id == id }) else { return }
        self.applySelection(account)
    }

    func _test_simulateRuntimeClick(id: String) -> Bool {
        guard let button = self.buttons.first(where: { $0.identifier?.rawValue == id }) else { return false }
        self.updateConstraintsForSubtreeIfNeeded()
        self.layoutSubtreeIfNeeded()
        let point = self.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        guard let mouseDownEvent = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: point,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1),
            let mouseUpEvent = NSEvent.mouseEvent(
                with: .leftMouseUp,
                location: point,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 2,
                clickCount: 1,
                pressure: 0)
        else {
            return false
        }
        self.mouseDown(with: mouseDownEvent)
        self.mouseUp(with: mouseUpEvent)
        return self.selectedAccountID == id
    }

    func _test_hitTestSwallowsChildButton(id: String) -> Bool {
        guard let button = self.buttons.first(where: { $0.identifier?.rawValue == id }) else { return false }
        self.updateConstraintsForSubtreeIfNeeded()
        self.layoutSubtreeIfNeeded()
        let point = self.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        return self.hitTest(point) === self
    }

    func _test_toolTipAfterHitTest(id: String) -> String? {
        guard let button = self.buttons.first(where: { $0.identifier?.rawValue == id }) else { return nil }
        self.updateConstraintsForSubtreeIfNeeded()
        self.layoutSubtreeIfNeeded()
        let point = self.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        _ = self.hitTest(point)
        return self.toolTip
    }
    #endif
}
