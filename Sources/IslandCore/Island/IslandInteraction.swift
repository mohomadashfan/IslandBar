import Foundation

/// Why the island is expanded. The reason decides which events collapse it again.
public enum ExpansionReason: Sendable, Equatable {
    /// Pointer is resting on the island; leaving collapses it.
    case hover
    /// User clicked; stays open until Escape, a click outside or another toggle.
    case click
    /// Opened from the keyboard shortcut; behaves like `click`.
    case shortcut
    /// Files are being dragged over the island.
    case drag
}

public enum IslandPresentation: Sendable, Equatable {
    case compact
    case expanded(ExpansionReason)

    public var isExpanded: Bool {
        if case .expanded = self { true } else { false }
    }

    /// Expanded in a way that should take keyboard focus (for Escape and text input).
    public var wantsKeyboardFocus: Bool {
        self == .expanded(.click) || self == .expanded(.shortcut)
    }
}

/// Events delivered after any hover/collapse delays have already elapsed.
public enum IslandEvent: Sendable, Equatable {
    case pointerEntered
    case pointerExited
    /// A click on the island that was not handled by a control inside it.
    case clicked
    case clickedOutside
    case escapePressed
    case shortcutPressed
    case dragEntered
    case dragExited
    case dropCompleted
}

public struct IslandInteractionPolicy: Sendable, Equatable {
    public var expandOnHover: Bool
    public var collapseOnClickOutside: Bool

    public init(expandOnHover: Bool = true, collapseOnClickOutside: Bool = true) {
        self.expandOnHover = expandOnHover
        self.collapseOnClickOutside = collapseOnClickOutside
    }

    public init(_ settings: GeneralSettings) {
        self.init(
            expandOnHover: settings.expandOnHover,
            collapseOnClickOutside: settings.collapseOnClickOutside
        )
    }
}

/// Pure state machine for the island's compact/expanded presentation.
public enum IslandInteraction {
    public static func reduce(
        _ state: IslandPresentation,
        _ event: IslandEvent,
        policy: IslandInteractionPolicy
    ) -> IslandPresentation {
        switch (state, event) {
        case (.compact, .pointerEntered):
            policy.expandOnHover ? .expanded(.hover) : .compact
        case (.compact, .clicked):
            .expanded(.click)
        case (.compact, .shortcutPressed):
            .expanded(.shortcut)
        case (.compact, .dragEntered):
            .expanded(.drag)
        case (.compact, _):
            .compact

        case (.expanded, .escapePressed), (.expanded, .shortcutPressed):
            .compact

        case (.expanded(.hover), .clicked):
            .expanded(.click)
        case (.expanded(.hover), .pointerExited), (.expanded(.hover), .clickedOutside):
            .compact

        case (.expanded(.drag), .dragExited):
            .compact
        case (.expanded(.drag), .dropCompleted):
            // Stay open to show the result; leaving the island now collapses it.
            .expanded(.hover)

        case (.expanded(.click), .clickedOutside), (.expanded(.shortcut), .clickedOutside):
            policy.collapseOnClickOutside ? .compact : state

        case (.expanded, _):
            state
        }
    }
}
