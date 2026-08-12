import SwiftUI

/** One page of settings, and how it appears in the window's toolbar. */
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case languages
    case corrections
    case apps
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .languages: return "Languages"
        case .corrections: return "Corrections"
        case .apps: return "Apps"
        case .privacy: return "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .languages: return "globe"
        case .corrections: return "checkmark.circle"
        case .apps: return "square.grid.2x2"
        case .privacy: return "hand.raised"
        }
    }

    /**
     How wide the window is on this page.

     Each page is sized to its own content, the way the preferences windows this
     is modelled on are: a page of checkboxes has no business being as wide as
     the one holding a list of applications.
     */
    var width: CGFloat {
        switch self {
        case .apps: return 620
        default: return 560
        }
    }

    @MainActor @ViewBuilder
    func view(model: AppModel) -> some View {
        switch self {
        case .general: GeneralSettingsView(preferences: model.preferences)
        case .languages: LanguageSettingsView(preferences: model.preferences)
        case .corrections: CorrectionSettingsView(preferences: model.preferences)
        case .apps: AppSettingsView(preferences: model.preferences)
        case .privacy: PrivacySettingsView()
        }
    }
}
