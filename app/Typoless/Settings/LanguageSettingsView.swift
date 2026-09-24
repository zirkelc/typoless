import SwiftUI

/**
 The languages Typoless corrects, and which model does each of them.

 A language is added rather than switched on, because the list of languages the
 app knows is longer than the list anyone writes in, and a page of seven
 checkboxes where two matter is a page that has to be read every time. What is
 not added is not detected, not corrected, and not shown under Corrections.
 */
struct LanguageSettingsView: View {
    @Bindable var preferences: Preferences

    @State private var selection: CorrectionLanguage?
    @State private var isAdding = false

    var body: some View {
        SettingsSurface {
            SettingsSection(
                footer: """
                Available languages that will be corrected. The language of each line \
                is detected. Override the default model per language.
                """
            ) {
                if added.isEmpty {
                    Text("No languages yet. Add one to start correcting.")
                        .settingsEmptyRow()
                }

                ForEach(added, id: \.self) { language in
                    LanguageRow(
                        language: language,
                        isSelected: selection == language,
                        model: modelBinding(for: language),
                        inUse: preferences.model(for: language),
                        onSelect: { selection = language }
                    )
                }
            } actions: {
                /**
                 A plain button opening a list, rather than a pop-up menu button.
                 A pop-up reads as "this is the current value", and adding a
                 language is an action rather than a choice being displayed.
                 */
                Button("Add Language…") { isAdding = true }
                    .disabled(available.isEmpty)
                    .popover(isPresented: $isAdding, arrowEdge: .bottom) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(available, id: \.self) { language in
                                Button {
                                    add(language)
                                    isAdding = false
                                } label: {
                                    HStack(spacing: 6) {
                                        Text(language.displayName)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(.vertical, 6)
                        .frame(width: 200)
                    }

                Button("Remove") { remove() }
                    .disabled(selection == nil || added.count <= 1)
            }
        }
    }

    private var added: [CorrectionLanguage] {
        preferences.enabledLanguages
    }

    private var available: [CorrectionLanguage] {
        CorrectionLanguage.allCases.filter { !added.contains($0) }
    }

    private func add(_ language: CorrectionLanguage) {
        update(language) { $0.isEnabled = true }
        selection = language
    }

    private func remove() {
        guard let selection, added.count > 1 else { return }

        update(selection) { $0.isEnabled = false }
        self.selection = nil
    }

    private func modelBinding(for language: CorrectionLanguage) -> Binding<ModelChoice?> {
        Binding(
            get: { preferences.languageSettings[language]?.model },
            set: { model in update(language) { $0.model = model } }
        )
    }

    private func update(_ language: CorrectionLanguage, _ change: (inout LanguageSettings) -> Void) {
        var settings = preferences.languageSettings
        var entry = settings[language] ?? .default(for: language)
        change(&entry)
        settings[language] = entry
        preferences.languageSettings = settings
    }
}

private struct LanguageRow: View {
    let language: CorrectionLanguage
    let isSelected: Bool
    @Binding var model: ModelChoice?
    /** The model this language actually uses, with "Default model" resolved. */
    let inUse: ModelChoice
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(language.displayName)

            advice

            Spacer()

            /**
             Every model, not only the downloaded ones. A language naming Apple's
             model while the default is a downloaded one is a real configuration,
             and it used to be unsayable: the choice was offered only when the
             global backend was already the local one, and could only name
             another local model.
             */
            Picker("", selection: $model) {
                Text("Default model").tag(ModelChoice?.none)
                Divider()
                Text(ModelChoice.appleOnDevice.displayName).tag(ModelChoice?.some(.appleOnDevice))
                ForEach(LocalModel.allCases, id: \.self) { option in
                    Text(option.displayName).tag(ModelChoice?.some(.local(option)))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .settingsRow()
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    /**
     Whether this language is being corrected by the model that measured best
     for it.

     A mark rather than a sentence, because it is true of most rows most of the
     time and a row of advice nobody needs is a row that gets skimmed. The
     sentence is in the tooltip, where it is read by the person who wondered
     what the mark meant.

     Which model is best is a measured fact per language, not a global one:
     Apple's model wins English, German, French and Dutch, and Gemma wins
     Spanish, Italian and Portuguese by between 13 and 25 points.
     */
    @ViewBuilder private var advice: some View {
        let best = language.bestModel

        if inUse == best.choice {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("\(best.choice.displayName) measured best for \(language.displayName), and is what this language uses.")
                .accessibilityLabel("Best model for \(language.displayName)")
        } else {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .help("\(best.choice.displayName) measured \(best.margin) points better for \(language.displayName) than what this language uses.")
                .accessibilityLabel("A better model is available for \(language.displayName)")
        }
    }
}

#Preview {
    LanguageSettingsView(preferences: Preferences())
}
