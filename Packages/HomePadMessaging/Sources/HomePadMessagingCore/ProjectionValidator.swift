import Foundation

/// Checks apps, templates, and hub actions against `ProjectionLimits`. Both ends run it: the
/// companion before sending and the hub on everything it receives.
public struct ProjectionValidator: Sendable, Equatable {
    public typealias Failure = ProjectionValidationError

    public let limits: ProjectionLimits

    public init(limits: ProjectionLimits = .standard) {
        self.limits = limits
    }

    // MARK: Apps

    public func validate(apps: [ProjectedApp]) throws(Failure) {
        try count(apps.count, atMost: limits.maxApps, field: "apps")
        try unique(apps.map(\.id), field: "app.id")
        for app in apps {
            try validate(app)
        }
    }

    public func validate(_ app: ProjectedApp) throws(Failure) {
        try identifier(app.id, field: "app.id")
        try requiredText(app.name, limit: limits.maxTitleLength, field: "app.name")
        try symbol(app.symbolName, field: "app.symbolName")
    }

    // MARK: Templates

    public func validate(_ template: ProjectionTemplate) throws(Failure) {
        try identifier(template.id, field: "template.id")
        try requiredText(template.title, limit: limits.maxTitleLength, field: "template.title")
        switch template {
        case .list(let list): try validate(list)
        case .grid(let grid): try buttons(grid.buttons, limit: limits.maxGridButtons, field: "grid.buttons")
        case .nowPlaying(let nowPlaying): try validate(nowPlaying)
        case .conversationList(let list): try validate(list)
        case .conversation(let conversation): try validate(conversation)
        case .information(let information): try validate(information)
        case .agenda(let agenda): try validate(agenda)
        }
    }

    private func validate(_ list: ListTemplate) throws(Failure) {
        try count(list.sections.count, atMost: limits.maxListSections, field: "list.sections")
        try unique(list.sections.map(\.id), field: "section.id")
        let rows = list.sections.flatMap(\.rows)
        try count(rows.count, atMost: limits.maxListRows, field: "list.rows")
        try unique(rows.map(\.id), field: "row.id")
        try optionalText(list.emptyMessage, limit: limits.maxSubtitleLength, field: "list.emptyMessage")
        for section in list.sections {
            try identifier(section.id, field: "section.id")
            try optionalText(section.header, limit: limits.maxTitleLength, field: "section.header")
        }
        for row in rows {
            try validate(row)
        }
    }

    private func validate(_ row: ProjectionRow) throws(Failure) {
        try identifier(row.id, field: "row.id")
        try requiredText(row.title, limit: limits.maxTitleLength, field: "row.title")
        try optionalText(row.subtitle, limit: limits.maxSubtitleLength, field: "row.subtitle")
        try optionalSymbol(row.symbolName, field: "row.symbolName")
        try optionalIdentifier(row.actionID, field: "row.actionID")
        switch row.accessory {
        case .none, .disclosure, .toggle:
            break
        case .badge(let badgeCount):
            guard badgeCount >= 0 else { throw .invalidCount(field: "row.badge") }
        case .detail(let detail):
            try optionalText(detail, limit: limits.maxTitleLength, field: "row.detail")
        }
    }

    private func buttons(_ buttons: [ProjectionButton], limit: Int, field: String) throws(Failure) {
        try count(buttons.count, atMost: limit, field: field)
        try unique(buttons.map(\.id), field: "button.id")
        for button in buttons {
            try identifier(button.id, field: "button.id")
            try requiredText(button.title, limit: limits.maxTitleLength, field: "button.title")
            try optionalSymbol(button.symbolName, field: "button.symbolName")
            try identifier(button.actionID, field: "button.actionID")
        }
    }

    private func validate(_ nowPlaying: NowPlayingTemplate) throws(Failure) {
        try optionalText(nowPlaying.artist, limit: limits.maxTitleLength, field: "nowPlaying.artist")
        try optionalText(nowPlaying.album, limit: limits.maxTitleLength, field: "nowPlaying.album")
        if let artwork = nowPlaying.artwork, artwork.count > limits.maxArtworkBytes {
            throw .artworkTooLarge(limit: limits.maxArtworkBytes)
        }
        guard nowPlaying.elapsed.isFinite, nowPlaying.duration.isFinite,
              nowPlaying.elapsed >= 0, nowPlaying.duration >= 0,
              nowPlaying.elapsed <= nowPlaying.duration || nowPlaying.duration == 0
        else { throw .invalidPlaybackTime }
        try unique(nowPlaying.commands.map(\.rawValue), field: "nowPlaying.commands")
    }

    private func validate(_ list: ConversationListTemplate) throws(Failure) {
        try count(list.conversations.count, atMost: limits.maxConversations, field: "conversations")
        try unique(list.conversations.map(\.id), field: "conversation.id")
        try optionalText(list.emptyMessage, limit: limits.maxSubtitleLength, field: "conversations.emptyMessage")
        for conversation in list.conversations {
            try identifier(conversation.id, field: "conversation.id")
            try requiredText(conversation.title, limit: limits.maxTitleLength, field: "conversation.title")
            try optionalText(conversation.preview, limit: limits.maxSubtitleLength, field: "conversation.preview")
            try identifier(conversation.actionID, field: "conversation.actionID")
            guard conversation.unreadCount >= 0 else { throw .invalidCount(field: "conversation.unreadCount") }
        }
    }

    private func validate(_ conversation: ConversationTemplate) throws(Failure) {
        try identifier(conversation.conversationID, field: "conversation.conversationID")
        try optionalText(conversation.recipientHandle, limit: limits.maxIdentifierLength, field: "conversation.recipientHandle")
        try count(conversation.bubbles.count, atMost: limits.maxBubbles, field: "conversation.bubbles")
        try unique(conversation.bubbles.map(\.id), field: "bubble.id")
        for bubble in conversation.bubbles {
            try identifier(bubble.id, field: "bubble.id")
            try requiredText(bubble.text, limit: limits.maxBodyLength, field: "bubble.text")
        }
    }

    private func validate(_ information: InformationTemplate) throws(Failure) {
        try count(information.items.count, atMost: limits.maxInformationItems, field: "information.items")
        try unique(information.items.map(\.id), field: "information.item.id")
        for item in information.items {
            try identifier(item.id, field: "information.item.id")
            try requiredText(item.label, limit: limits.maxTitleLength, field: "information.label")
            try optionalText(item.value, limit: limits.maxSubtitleLength, field: "information.value")
        }
        try buttons(information.buttons, limit: limits.maxInformationButtons, field: "information.buttons")
    }

    private func validate(_ agenda: AgendaTemplate) throws(Failure) {
        try count(agenda.entries.count, atMost: limits.maxAgendaEntries, field: "agenda.entries")
        try unique(agenda.entries.map(\.id), field: "agenda.entry.id")
        try optionalText(agenda.emptyMessage, limit: limits.maxSubtitleLength, field: "agenda.emptyMessage")
        for entry in agenda.entries {
            try identifier(entry.id, field: "agenda.entry.id")
            try requiredText(entry.title, limit: limits.maxTitleLength, field: "agenda.title")
            try optionalText(entry.detail, limit: limits.maxSubtitleLength, field: "agenda.detail")
            try optionalIdentifier(entry.actionID, field: "agenda.actionID")
        }
    }

    // MARK: Hub actions

    public func validate(appID: String) throws(Failure) {
        try identifier(appID, field: "appID")
    }

    public func validate(actionID: String, payload: [String: String]) throws(Failure) {
        try identifier(actionID, field: "actionID")
        try count(payload.count, atMost: limits.maxActionPayloadEntries, field: "action.payload")
        for (key, value) in payload {
            try identifier(key, field: "action.payload.key")
            try optionalText(value, limit: limits.maxBodyLength, field: "action.payload.value")
        }
    }

    public func validate(conversationID: String, replyText: String) throws(Failure) {
        try identifier(conversationID, field: "conversationID")
        guard !replyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .emptyText(field: "reply.text")
        }
        try optionalText(replyText, limit: limits.maxBodyLength, field: "reply.text")
    }

    // MARK: Primitives

    private func count(_ count: Int, atMost limit: Int, field: String) throws(Failure) {
        guard count <= limit else { throw .tooManyItems(field: field, limit: limit) }
    }

    private func unique(_ identifiers: [String], field: String) throws(Failure) {
        guard Set(identifiers).count == identifiers.count else { throw .duplicateIdentifier(field: field) }
    }

    /// Identifiers are opaque, but they may not be empty or carry whitespace or control characters.
    public func isUsableIdentifier(_ value: String) -> Bool {
        let isClean = value.unicodeScalars.allSatisfy { scalar in
            !CharacterSet.controlCharacters.contains(scalar) && !CharacterSet.whitespacesAndNewlines.contains(scalar)
        }
        return !value.isEmpty && value.count <= limits.maxIdentifierLength && isClean
    }

    private func identifier(_ value: String, field: String) throws(Failure) {
        guard isUsableIdentifier(value) else { throw .invalidIdentifier(field: field) }
    }

    private func optionalIdentifier(_ value: String?, field: String) throws(Failure) {
        if let value {
            try identifier(value, field: field)
        }
    }

    private func requiredText(_ value: String, limit: Int, field: String) throws(Failure) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw .emptyText(field: field) }
        try optionalText(value, limit: limit, field: field)
    }

    private func optionalText(_ value: String?, limit: Int, field: String) throws(Failure) {
        if let value, value.count > limit {
            throw .textTooLong(field: field, limit: limit)
        }
    }

    private func symbol(_ value: String, field: String) throws(Failure) {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.")
        guard !value.isEmpty, value.count <= 64, value.unicodeScalars.allSatisfy(allowed.contains) else {
            throw .invalidSymbolName(field: field)
        }
    }

    private func optionalSymbol(_ value: String?, field: String) throws(Failure) {
        if let value {
            try symbol(value, field: field)
        }
    }
}
