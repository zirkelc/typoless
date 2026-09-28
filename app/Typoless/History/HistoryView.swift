import AppKit
import SwiftUI

/**
 The widths every row and the header above them share.

 One place, because a header that does not line up with its rows is worse than
 no header: it claims an order the eye then has to check.
 */
enum HistoryColumn {
    static let app: CGFloat = 165
    static let time: CGFloat = 52
    static let changes: CGFloat = 122
    static let language: CGFloat = 115
    static let model: CGFloat = 130
    static let spacing: CGFloat = 12

    /** The card's own padding, so the header starts where a row's first word does. */
    static let inset: CGFloat = 32
}

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
     What the list is narrowed to.

     Held here rather than in the history itself, because a filter is a way of
     looking at the record and not part of it: closing the window and opening it
     again should show everything, which is what somebody expects of a list they
     did not change.
     */
    @State private var app: String?
    @State private var language: CorrectionLanguage?
    @State private var show: ShowFilter = .all

    /** Which passes to list, by what happened rather than by where. */
    enum ShowFilter: String, CaseIterable, Identifiable {
        case all = "Everything"
        case changed = "Changed something"
        case refused = "Refused something"

        var id: String { rawValue }

        func matches(_ entry: CorrectionHistory.Entry) -> Bool {
            switch self {
            case .all: return true
            case .changed: return entry.didChange
            case .refused: return entry.outcome.notes.contains { !$0.isApplied }
            }
        }
    }

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
            if !history.entries.isEmpty {
                header
                Divider()
            }

            if history.entries.isEmpty {
                empty
            } else if entries.isEmpty {
                nothingMatches
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(entries) { entry in
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
        .frame(width: 900, height: 580)
        .onAppear { history.prune() }
    }

    /** What is listed once the filters have had their say. */
    private var entries: [CorrectionHistory.Entry] {
        history.entries.filter { entry in
            (app == nil || entry.bundleID == app)
                && (language == nil || entry.outcome.languages.contains { $0 == language })
                && show.matches(entry)
        }
    }

    /** Only the apps and languages that are actually in the list, so no filter finds nothing. */
    private var apps: [String] {
        Array(Set(history.entries.compactMap(\.bundleID))).sorted {
            name(of: $0).localizedCaseInsensitiveCompare(name(of: $1)) == .orderedAscending
        }
    }

    private var languages: [CorrectionLanguage] {
        CorrectionLanguage.allCases.filter { candidate in
            history.entries.contains { $0.outcome.languages.contains(candidate) }
        }
    }

    private func name(of bundleID: String) -> String {
        InstalledApp.named(bundleID).name
    }

    /**
     The head of the table, which is also where the filtering is.

     A filter bar of its own sat above columns it did not line up with, and read
     as a second header disagreeing with the first. Here each menu is the column
     it filters, so the thing being narrowed is named once. Time and Model have
     no menu, because neither answers a question anybody asks of this list.
     */
    private var header: some View {
        HStack(spacing: HistoryColumn.spacing) {
            Menu {
                Button("All apps") { app = nil }
                Divider()
                ForEach(apps, id: \.self) { bundleID in
                    Button(name(of: bundleID)) { app = bundleID }
                }
            } label: {
                title("App", value: app.map(name(of:)))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: HistoryColumn.app, alignment: .leading)

            Text("Time")
                .frame(width: HistoryColumn.time, alignment: .leading)

            Menu {
                ForEach(ShowFilter.allCases) { option in
                    Button(option.rawValue) { show = option }
                }
            } label: {
                title("Changes", value: show == .all ? nil : show.rawValue)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: HistoryColumn.changes, alignment: .leading)

            Menu {
                Button("All languages") { language = nil }
                Divider()
                ForEach(languages) { candidate in
                    Button(candidate.displayName) { language = candidate }
                }
            } label: {
                title("Language", value: language?.displayName)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .frame(width: HistoryColumn.language, alignment: .leading)
            .disabled(languages.isEmpty)

            Text("Model")
                .frame(width: HistoryColumn.model, alignment: .leading)

            Spacer(minLength: 0)

            Text(summary)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, HistoryColumn.inset)
        .padding(.vertical, 8)
    }

    /**
     A column's name, or what it has been narrowed to.

     The name is the resting state and the value replaces it, so a filter that
     is on is visible from the shape of the header rather than from a badge
     somewhere else.
     */
    private func title(_ name: String, value: String?) -> some View {
        HStack(spacing: 3) {
            Text(value ?? name)
                .foregroundStyle(value == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                .lineLimit(1)

            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
                .foregroundStyle(.tertiary)
        }
    }

    private var summary: String {
        let shown = entries.count
        let total = history.entries.count

        guard shown != total else {
            return total == 1 ? "1 correction" : "\(total) corrections"
        }

        return "\(shown) of \(total)"
    }

    private var nothingMatches: some View {
        VStack(spacing: 6) {
            Text("Nothing matches")
                .font(.headline)

            Button("Show everything") {
                app = nil
                language = nil
                show = .all
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
     Where each change sits, on both sides.

     Worked out once per row rather than per read: as a computed property this
     ran on every `body` evaluation, and twice each time, and each call copies
     both versions of the text in full, which for a long email is not free.
     */
    private var changes: (before: [CFRange], after: [CFRange]) {
        let edits = TextDiff.edits(from: entry.before, to: entry.after).map { edit in
            FieldEdit(
                range: CFRange(
                    location: edit.range.lowerBound.utf16Offset(in: entry.before),
                    length: edit.range.upperBound.utf16Offset(in: entry.before)
                        - edit.range.lowerBound.utf16Offset(in: entry.before)
                ),
                replacement: edit.replacement
            )
        }

        /**
         Empty ranges are kept on the before side. An insertion has nothing to
         mark there, but it is still where the change happened, and dropping it
         would leave a long field with no change to centre the window on.
         */
        return (edits.map(\.range), edits.landedRanges)
    }

    var body: some View {
        let changes = self.changes
        VStack(alignment: .leading, spacing: 8) {
            /**
             The same columns as the header, in the same order and at the same
             widths, so the two read as one table. The text below spans the
             whole row instead, because a paragraph in a column is a column of
             one word.
             */
            HStack(spacing: HistoryColumn.spacing) {
                HStack(spacing: 5) {
                    if let app {
                        Image(nsImage: app.icon)
                            .resizable()
                            .frame(width: 14, height: 14)

                        Text(app.name)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else {
                        Text("Unknown app")
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: HistoryColumn.app, alignment: .leading)

                Text(entry.date, style: .time)
                    .foregroundStyle(.secondary)
                    .frame(width: HistoryColumn.time, alignment: .leading)

                Text(changeCount)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: HistoryColumn.changes, alignment: .leading)

                Text(languages)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: HistoryColumn.language, alignment: .leading)

                Text(models)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: HistoryColumn.model, alignment: .leading)

                Spacer(minLength: 0)

                Button("Copy") { copyOriginal() }
                    .controlSize(.small)
                    .help("Copies the text as you wrote it, before the correction.")

                Button("Report…") { isConfirmingReport = true }
                    .controlSize(.small)
                    .help("Opens a prefilled issue on GitHub. Nothing is posted until you submit it.")
            }
            .font(.callout)

            excerpt("Before", of: entry.before, highlighting: changes.before, tint: .red)

            if entry.didChange {
                excerpt("After", of: entry.after, highlighting: changes.after, tint: .green)
            }

            if !entry.outcome.notes.isEmpty {
                decisions
            }
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

    /** Empty reads as a dash rather than as a gap, which looks like a bug. */
    private var languages: String {
        entry.outcome.languages.isEmpty
            ? "—"
            : entry.outcome.languages.map(\.displayName).joined(separator: ", ")
    }

    private var models: String {
        entry.models.isEmpty ? "—" : entry.models.joined(separator: ", ")
    }

    private var changeCount: String {
        switch entry.editCount {
        case 0: return "Nothing changed"
        case 1: return "1 change"
        default: return "\(entry.editCount) changes"
        }
    }

    /**
     Every change the pass offered, and what happened to it.

     The refused ones are the reason this list exists. A user looking at text
     that was not corrected has no way to tell a model that saw nothing from a
     rule that forbade the fix, and until now neither had anybody they asked.
     */
    private var decisions: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(entry.outcome.notes) { note in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: note.isApplied ? "checkmark.circle.fill" : "minus.circle")
                        .foregroundStyle(note.isApplied ? Color.green : Color.secondary)
                        .frame(width: 44, alignment: .trailing)

                    Text(note.description)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let refusal = note.refusal {
                        Text(refusal.summary)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
        .font(.callout)
        .padding(.top, 2)
    }

    private func excerpt(
        _ label: String,
        of text: String,
        highlighting ranges: [CFRange],
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)

            Text(styled(TextExcerpt.build(from: text, highlighting: ranges), tint: tint))
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /**
     Dims everything the correction did not touch, so the eye lands on the words
     that moved rather than on a paragraph of unchanged prose.
     */
    private func styled(_ excerpt: TextExcerpt, tint: Color) -> AttributedString {
        var result = AttributedString(excerpt.text)
        result.foregroundColor = .secondary

        for change in excerpt.highlights {
            guard
                let lower = AttributedString.Index(change.lowerBound, within: result),
                let upper = AttributedString.Index(change.upperBound, within: result)
            else { continue }

            result[lower..<upper].backgroundColor = tint.opacity(0.22)
            result[lower..<upper].foregroundColor = .primary
        }

        return result
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
            environment: .current,
            outcome: entry.outcome
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
    history.addSamples()

    return HistoryView(history: history, onOpenSettings: {}, describeModel: { "Apple on-device" })
}
