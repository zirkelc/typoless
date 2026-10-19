import SwiftUI

/**
 What the app does, drawn as the keys that do it.

 Both triggers can be changed from here, which makes this page the teaching and
 the setting at once. That is deliberate: the gesture is the one thing somebody
 has to remember after setup closes, and the surest way to remember it is to
 have chosen it.
 */
struct TriggersPage: View {
    @Bindable var preferences: Preferences

    var body: some View {
        OnboardingCard {
            doubleTap
            OnboardingDivider()
            shortcut
            OnboardingDivider()
            undo
        }
    }

    private var doubleTap: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(spacing: 4) {
                Keycap(label: preferences.doubleTapModifier.symbol)
                Keycap(label: preferences.doubleTapModifier.symbol)
            }
            .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Toggle("Double-tap", isOn: $preferences.isDoubleTapEnabled)
                    .toggleStyle(.checkbox)

                Text(preferences.doubleTapModifier.caution
                    ?? "Tap it twice, quickly, with no other key or click in between.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Picker("", selection: $preferences.doubleTapModifier) {
                ForEach(TapModifier.allCases, id: \.self) { modifier in
                    Text(modifier.displayName).tag(modifier)
                }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(!preferences.isDoubleTapEnabled)
        }
        .onboardingRow()
    }

    private var shortcut: some View {
        HStack(alignment: .top, spacing: 12) {
            /**
             A tile rather than the keys themselves. The combination is already
             written out in the recorder at the end of this row, and a shortcut
             with three modifiers and a named key is five keys wide, which is
             wider than the column the other two rows line up against.
             */
            KeycapSymbol(symbol: "keyboard")
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Toggle("Keyboard shortcut", isOn: $preferences.isHotKeyEnabled)
                    .toggleStyle(.checkbox)

                Text("One key combination, pressed once.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            ShortcutRecorder(shortcut: $preferences.hotKey)
                .disabled(!preferences.isHotKeyEnabled)
        }
        .onboardingRow()
    }

    /**
     The promise that makes the other two rows safe to try.

     Nothing to set, which is why it is last. Somebody who has just read that
     an app will rewrite what they type wants to know what it would take to
     get their own words back, and the answer is one gesture.
     */
    private var undo: some View {
        HStack(alignment: .top, spacing: 12) {
            KeycapSymbol(symbol: "arrow.uturn.backward")
                .frame(width: 56, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text("Undo")

                Text("Every correction can be undone, and each one is kept in History until you quit.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
        }
        .onboardingRow()
    }
}

/** The two gates, each with the button that opens the right pane of System Settings. */
struct PermissionsPage: View {
    let permissions: PermissionsModel

    var body: some View {
        OnboardingCard {
            PermissionRow(
                symbol: "accessibility",
                title: "Accessibility",
                rationale: "Lets Typoless read the text in the field you are typing in, and write the corrections back.",
                isSatisfied: permissions.isAccessibilityTrusted,
                isWaiting: permissions.isAwaitingAccessibility,
                actionTitle: permissions.isAwaitingAccessibility ? "Open Settings" : "Allow",
                action: { permissions.requestAccessibility() },
                note: permissions.accessibilityNote
            )

            OnboardingDivider()

            PermissionRow(
                symbol: "sparkles",
                title: "Apple Intelligence",
                rationale: permissions.modelAvailability.explanation,
                isSatisfied: permissions.modelAvailability == .available,
                isWaiting: false,
                actionTitle: permissions.modelAvailability.isActionable ? "Allow" : nil,
                action: permissions.modelAvailability.isActionable
                    ? { permissions.openAppleIntelligenceSettings() }
                    : nil
            )
        }
    }
}

/**
 Which languages are corrected.

 Tick boxes here rather than the add-and-remove list Settings uses. Setup is
 where someone meets the idea for the first time, and a list of everything the
 app knows says what the choice is; the Settings page assumes it is already
 understood and optimises for changing it.
 */
struct LanguagesPage: View {
    @Bindable var preferences: Preferences

    var body: some View {
        OnboardingCard {
            ForEach(Array(CorrectionLanguage.allCases.enumerated()), id: \.element) { index, language in
                if index > 0 {
                    OnboardingDivider()
                }

                /**
                 No qualifier beside the name any more. It said "not measured"
                 for the five languages that had no dataset, and now every one
                 of the seven has one and has been scored against all three
                 models. What differs between them is which model is best, and
                 that is answered where the model is chosen, not here.
                 */
                Toggle(isOn: binding(for: language)) {
                    Text(language.displayName)
                }
                .toggleStyle(.checkbox)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func binding(for language: CorrectionLanguage) -> Binding<Bool> {
        Binding(
            get: { preferences.languageSettings[language]?.isEnabled ?? false },
            set: { isEnabled in
                var settings = preferences.languageSettings
                var entry = settings[language] ?? .default(for: language)
                entry.isEnabled = isEnabled
                settings[language] = entry
                preferences.languageSettings = settings
            }
        )
    }
}

/**
 The end of setup: the user corrects a real field with their own trigger.

 The field is ours and the pass is not. It runs through the same accessibility
 read and write as any other application, so what proves the setup is the text
 changing here, not a message from us saying that it should.

 There is a button as well, for anyone who turned both triggers off or whose
 keyboard makes the gesture awkward. It is the fallback rather than the
 instruction: pressing the real trigger once is what makes it stick.
 */
struct TryItPage: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SampleField(
                model: model,
                caption: "The whole field",
                sample: "i  think its ready , lets see if this works",
                instruction: "with the cursor anywhere in the field.",
                done: "Typoless corrected the whole field."
            )

            /**
             The second example is the one nobody discovers on their own.

             Selecting first is how the app is told to leave the rest alone,
             which matters most in the message someone has half written and
             does not want reflowed. It is one sentence of teaching here and a
             support question otherwise.
             */
            SampleField(
                model: model,
                caption: "Or only what you select",
                sample: "thanks for the update. i will check teh numbers and come back to you",
                instruction: "after selecting a few words. Only the selection changes.",
                done: "Typoless corrected only the words you selected."
            )
        }
    }
}

/**
 What happens after a correction lands: it is kept, and it can be taken back.

 Last, and its own step, because it answers the question the page before it
 raises. Someone who has just watched an app change their text wants to know
 what it would take to undo that, and the honest answer is a list with their own
 correction in it rather than a sentence promising one.

 The retention setting is here rather than only in Settings for the same reason:
 this is the moment the user learns that something is kept at all, so it is the
 moment to say for how long and to let them change it.
 */
struct HistoryPage: View {
    @Bindable var preferences: Preferences
    let history: CorrectionHistory

    var body: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Keep corrections for")

                    Spacer()

                    Picker("", selection: $preferences.historyRetention) {
                        ForEach(HistoryRetention.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }

                Text(preferences.historyRetention.keepsHistory
                    ? "In memory only, never written to disk, and cleared when Typoless quits. Undo covers the last correction; History covers the rest."
                    : "Nothing is kept. Undo still covers the correction you just made, and nothing before it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .onboardingRow()

            OnboardingDivider()

            entries
                .onboardingRow()
        }
    }

    @ViewBuilder private var entries: some View {
        if history.entries.isEmpty {
            Text("No corrections yet. Go back a step and fix one of the samples to see it here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(history.entries.prefix(2)) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.before)
                            .strikethrough()
                            .foregroundStyle(.secondary)
                        Text(entry.after)
                    }
                    .font(.callout)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Text("Open History from the menu bar to put any of these back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/** One sample field: what to do, the field itself, and what happened. */
private struct SampleField: View {
    let model: AppModel
    let caption: String
    let sample: String
    let instruction: String
    let done: String

    @State private var text: String
    @State private var hasChanged = false
    @FocusState private var isFocused: Bool

    init(model: AppModel, caption: String, sample: String, instruction: String, done: String) {
        self.model = model
        self.caption = caption
        self.sample = sample
        self.instruction = instruction
        self.done = done
        _text = State(initialValue: sample)
    }

    var body: some View {
        OnboardingCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(caption)
                    .font(.headline)

                TextEditor(text: $text)
                    .focused($isFocused)
                    .font(.body)
                    .frame(height: 48)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .onChange(of: text) { _, new in
                        if new != sample { hasChanged = true }
                    }

                HStack(spacing: 10) {
                    if hasChanged {
                        Label(done, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)

                        Button("Again") {
                            text = sample
                            hasChanged = false
                            isFocused = true
                        }
                        .buttonStyle(.link)
                    } else {
                        Text(instructionLine)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    /**
                     The pass reads whichever field has focus, and a click moves
                     focus to the button on a Mac with full keyboard access, so the
                     field is focused again before anything is asked. A selection
                     made by hand survives that, since focus returns to where it was.
                     */
                    Button("Fix") {
                        isFocused = true
                        model.trigger()
                    }
                    .disabled(model.isPaused)
                }
                .font(.subheadline)
            }
            .onboardingRow()
        }
    }

    private var instructionLine: String {
        guard let description = model.preferences.triggerDescription else {
            return "Both triggers are off, so use the button."
        }

        return "\(description) \(instruction)"
    }
}
