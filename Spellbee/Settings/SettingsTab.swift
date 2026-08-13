import SwiftUI

/** One page of settings, and how it appears in the window's toolbar. */
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case models
    case languages
    case corrections
    case apps
    case privacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .models: return "Models"
        case .languages: return "Languages"
        case .corrections: return "Corrections"
        case .apps: return "Apps"
        case .privacy: return "Privacy"
        }
    }

    var symbolName: String {
        switch self {
        case .general: return "gearshape"
        case .models: return "cpu"
        case .languages: return "globe"
        case .corrections: return "checkmark.circle"
        case .apps: return "square.grid.2x2"
        case .privacy: return "hand.raised"
        }
    }

    /**
     One width for every page.

     Sizing each page to its own content made the window jump about as the
     toolbar was clicked, which reads as the app losing its place rather than as
     a tidy fit. Height still follows the page, since that never moves under the
     pointer.
     */
    var width: CGFloat { SettingsSurface<EmptyView>.width }

    @MainActor @ViewBuilder
    func view(model: AppModel) -> some View {
        switch self {
        case .general: GeneralSettingsView(preferences: model.preferences)
        case .models: ModelSettingsView(model: model)
        case .languages: LanguageSettingsView(preferences: model.preferences)
        case .corrections: CorrectionSettingsView(preferences: model.preferences)
        case .apps: AppSettingsView(preferences: model.preferences)
        case .privacy: PrivacySettingsView()
        }
    }
}
