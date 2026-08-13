import SwiftUI

/**
 The languages Spellbee corrects, and which model does each of them.

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
            Table {
                if added.isEmpty {
                    Text("No languages yet. Add one to start correcting.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(added.enumerated()), id: \.element) { index, language in
                    if index > 0 {
                        Divider()
                    }

                    LanguageRow(
                        language: language,
                        isSelected: selection == language,
                        model: modelBinding(for: language),
                        onSelect: { selection = language }
                    )
                }
            }

            HStack(spacing: 8) {
                /**
                 A plain button opening a list, rather than a pop-up menu button.
                 A pop-up reads as "this is the current value", and adding a
                 language is an action rather than a choice being displayed.
                 */
                Button("Add…") { isAdding = true }
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
                                        if !language.isTuned {
                                            Image(systemName: "questionmark.circle")
                                                .foregroundStyle(.tertiary)
                                        }
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

                Spacer()
            }

            SettingsFootnote("""
            The language of each paragraph is detected, and only the languages \
            listed here are considered. A model set here overrides the default \
            under Models for that language alone.
            """)
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

    private func modelBinding(for language: CorrectionLanguage) -> Binding<LocalModel?> {
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
    @Binding var model: LocalModel?
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(language.displayName)
                .fontWeight(.medium)

            if !language.isTuned {
                Image(systemName: "questionmark.circle")
                    .foregroundStyle(.tertiary)
                    .help("Not measured. English and German are scored against a dataset; this one uses the same wording with the language named, and its quality is unknown.")
            }

            Spacer()

            Picker("", selection: $model) {
                Text("Default model").tag(LocalModel?.none)
                Divider()
                ForEach(LocalModel.allCases, id: \.self) { option in
                    Text(option.displayName).tag(LocalModel?.some(option))
                }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.15) : .clear)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}

#Preview {
    LanguageSettingsView(preferences: Preferences())
}
