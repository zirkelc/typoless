import AppKit
import SwiftUI

/**
 The setup checklist.

 Rows poll their own status, so granting a permission in System Settings turns
 the row green without the user coming back and clicking anything. The final
 step is a live text field inside our own window: the user should see the whole
 pipeline work somewhere harmless before pointing it at a real message.
 */
struct OnboardingView: View {
    let model: AppModel
    let onDone: () -> Void

    @AppStorage(DefaultsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false
    @State private var sampleText = "i  think its ready , lets see if this works"

    private var permissions: PermissionsModel { model.permissions }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                accessibilityRow
                intelligenceRow
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Divider()

            tryItOut

            Divider()

            footer
        }
        .frame(width: 520)
        /**
         Starting and stopping the poller belongs to the window controller, which
         is told when it closes; this view is not. Re-arming the triggers is
         already wired through `PermissionsModel.onChange`, so doing it here as
         well only made it look as though it happened solely while setup was open.
         */
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var accessibilityRow: PermissionRow {
        PermissionRow(
            title: "Accessibility",
            rationale: "Lets Spellbee read the text in the field you are typing in, and write the corrections back.",
            isSatisfied: permissions.isAccessibilityTrusted,
            actionTitle: "Open Settings…",
            action: { permissions.openAccessibilitySettings() }
        )
    }

    private var intelligenceRow: PermissionRow {
        let availability = permissions.modelAvailability
        let canAct = availability.isActionable

        return PermissionRow(
            title: "Apple Intelligence",
            rationale: availability.explanation,
            isSatisfied: availability == .available,
            actionTitle: canAct ? "Open Settings…" : nil,
            action: canAct ? { permissions.openAppleIntelligenceSettings() } : nil
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Set Up Spellbee")
                .font(.largeTitle.bold())
            Text("Two things to allow. Everything runs on this Mac; your text is never sent anywhere.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var tryItOut: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Try it out")
                .font(.headline)
            Text("Correcting this field uses the same path as any other app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextEditor(text: $sampleText)
                .font(.body)
                .frame(height: 60)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            /** Wired up once the trigger and accessibility layers exist. */
            Button("Fix This Text") {}
                .disabled(true)
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            if permissions.isReady {
                Label("Ready to go", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else {
                Text("Spellbee stays inactive until both are allowed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Done") {
                hasCompletedOnboarding = true
                onDone()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!permissions.isReady)
        }
        .padding(20)
    }
}
