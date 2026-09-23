import AppKit
import SwiftUI

/**
 The last few hours of corrections, newest first.

 Shows the text around each change rather than the whole field, because the
 question being asked is "what did it do to this", and eight hundred characters
 of unchanged prose does not answer it. The full original is still what gets
 copied, since that is what a restore needs.
 */
struct HistoryView: View {
    let history: CorrectionHistory

    /**
     Opens the setting that governs this window.

     Named here rather than only described in words, because the retention is
     the thing people question while looking at the list, and being told where
     the switch lives is worse than being taken to it.
     */
    let onOpenSettings: () -> Void

    /**
     Which model is answering now, for a report on an entry that did not
     record its own models. The model is the first thing anyone reading the
     report will want to know.
     */
    let describeModel: () -> String

    var body: some View {
        VStack(spacing: 0) {
            if history.entries.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(history.entries) { entry in
                            HistoryRow(entry: entry, describeModel: describeModel)
                        }
                    }
                    .padding(20)
                }
            }

            Divider()

            HStack(spacing: 6) {
                Text(history.retention.footnote)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button("Change…") { onOpenSettings() }
                    .buttonStyle(.link)
                    .font(.callout)

                Spacer()

                Button("Clear") { history.clear() }
                    .disabled(history.entries.isEmpty)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 720, height: 540)
        .onAppear { history.prune() }
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)

            Text(history.retention.keepsHistory ? "No corrections yet" : "History is off")
                .font(.headline)

            Text(history.retention.keepsHistory
                ? "Anything Typoless changes shows up here, with what it replaced."
                : "Turn it back on to be able to undo a correction later.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HistoryRow: View {
    let entry: CorrectionHistory.Entry
    let describeModel: () -> String

    @State private var isShowingClipboardNotice = false
    @State private var isConfirmingReport = false

    /** Resolved once per row rather than on each redraw, since it hits LaunchServices. */
    private var app: InstalledApp? {
        entry.bundleID.map(InstalledApp.named)
    }

    /**
     Worked out once per row rather than per read.

     As a computed property this ran on every `body` evaluation, and twice each
     time, since the after-range derives from it. Each call copies both the
     before and after text in full, which for a long email is not free.
     */
    private var span: (range: CFRange, replacement: String)? {
        TextDiff.differingSpan(from: entry.before, to: entry.after)
    }

    var body: some View {
        let span = self.span
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let app {
                    Image(nsImage: app.icon)
                        .resizable()
                        .frame(width: 14, height: 14)

                    Text(app.name)
                        .fontWeight(.medium)
                }

                Text(entry.date, style: .time)
                    .foregroundStyle(.secondary)

                Text(entry.editCount == 1 ? "1 change" : "\(entry.editCount) changes")
                    .foregroundStyle(.secondary)

                if !entry.models.isEmpty {
                    Text(entry.models.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Copy Original") { copyOriginal() }
                    .controlSize(.small)

                Button("Report…") { isConfirmingReport = true }
                    .controlSize(.small)
                    .help("Opens a prefilled issue on GitHub. Nothing is posted until you submit it.")
            }
            .font(.callout)

            excerpt("Before", of: entry.before, highlighting: span?.range, tint: .red)
            excerpt("After", of: entry.after, highlighting: afterRange(of: span), tint: .green)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        }
        .alert("The report is on the clipboard", isPresented: $isShowingClipboardNotice) {
            Button("OK") {}
        } message: {
            Text("""
            This correction is too long to carry in a link, so it has been \
            copied instead. Paste it into the issue that just opened.
            """)
        }
        /**
         Asked every time, with no way to switch it off. The text in a report is
         the user's own writing, and the tracker is public: that is worth one
         click, every time, from an app whose whole promise is that text stays
         on the Mac.
         */
        .confirmationDialog(
            "Report this correction on GitHub?",
            isPresented: $isConfirmingReport,
            titleVisibility: .visible
        ) {
            Button("Open GitHub…") { report() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            The issue is filled in for you, including the text before and after, \
            and it opens in your browser. The tracker is public, so read it and \
            delete anything you would rather not share. Nothing is posted until \
            you press Submit there.
            """)
        }
    }

    /**
     Where the replacement landed.

     It starts where the removed text did, since everything before that point is
     shared by definition, and runs for as long as what replaced it.
     */
    private func afterRange(of span: (range: CFRange, replacement: String)?) -> CFRange? {
        guard let span else { return nil }

        return CFRange(location: span.range.location, length: span.replacement.utf16.count)
    }

    private func excerpt(
        _ label: String,
        of text: String,
        highlighting range: CFRange?,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text(styled(TextExcerpt.build(from: text, highlighting: range), tint: tint))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /**
     Dims everything the correction did not touch, so the eye lands on the part
     that moved rather than on a paragraph of unchanged prose.
     */
    private func styled(_ excerpt: TextExcerpt, tint: Color) -> AttributedString {
        var context = AttributedString(excerpt.before)
        context.foregroundColor = .secondary

        /**
         A pure insertion has nothing to show on the removed side, and an empty
         highlight reads as though nothing happened, so it gets a mark instead.
         */
        var changed = AttributedString(excerpt.changed.isEmpty ? "▸" : excerpt.changed)
        changed.backgroundColor = tint.opacity(0.22)
        changed.foregroundColor = .primary

        var trailing = AttributedString(excerpt.after)
        trailing.foregroundColor = .secondary

        return context + changed + trailing
    }

    private func copyOriginal() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.before, forType: .string)
    }

    /**
     Opens the issue form, filled in but unsubmitted.

     The user reads it, edits or deletes anything they would rather not share,
     and submits it themselves. This is the only place text leaves the Mac, so
     it leaves by their hand and in plain sight.
     */
    private func report() {
        let report = CorrectionReport(
            before: entry.before,
            after: entry.after,
            appName: app?.name,
            bundleID: entry.bundleID,
            editCount: entry.editCount,
            backend: entry.models.isEmpty ? describeModel() : entry.models.joined(separator: ", "),
            environment: .current
        )

        if let url = report.url {
            NSWorkspace.shared.open(url)
            return
        }

        /**
         A long field makes a link the tracker answers with an error rather than
         a form, so the body travels on the clipboard and the form opens empty.
         */
        guard let blank = report.blankIssueURL else { return }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.body, forType: .string)
        NSWorkspace.shared.open(blank)
        isShowingClipboardNotice = true
    }
}

#Preview {
    let history = CorrectionHistory()
    history.record(
        before: "i think we shoud meet on tuesday, does that work for you",
        after: "I think we should meet on Tuesday, does that work for you",
        bundleID: "com.apple.Mail",
        editCount: 3,
        models: ["Apple on-device"]
    )

    return HistoryView(history: history, onOpenSettings: {}, describeModel: { "Apple on-device" })
}
