import AppKit
import SwiftUI

/**
 The models available, and which one corrects by default.

 Downloading is offered here rather than happening as a side effect of choosing
 a model. Those are two different intentions: picking a model is a decision
 about quality, and fetching several gigabytes is a decision about time and
 disk, and someone may well want the second done before they need it.
 */
struct ModelSettingsView: View {
    let model: AppModel

    var body: some View {
        SettingsSurface {
            SettingsSection(
                "Default model",
                footer: """
                Default model for every language. Can be overridden per language \
                in Languages.
                """
            ) {
                ModelRow(
                    title: CorrectorBackend.appleOnDevice.displayName,
                    detail: "Built in, nothing to download",
                    isDefault: model.preferences.backend == .appleOnDevice,
                    isTuned: true,
                    onMakeDefault: { model.use(.appleOnDevice) },
                    state: .ready
                )

                ForEach(LocalModel.allCases, id: \.self) { local in
                    ModelRow(
                        title: local.displayName,
                        detail: detail(for: local),
                        isDefault: model.preferences.backend == .local
                            && model.preferences.localModel == local,
                        isTuned: local == .gemma4_e4b,
                        onMakeDefault: { model.use(.local, model: local) },
                        state: state(of: local),
                        onDownload: { model.download(local) },
                        onCancel: { model.cancelDownload(of: local) },
                        onRemove: { confirmRemoval(of: local) }
                    )
                }
            }
        }
    }

    private func detail(for local: LocalModel) -> String {
        local.isDownloaded ? "Downloaded" : "\(local.approximateSize) download"
    }

    private func state(of local: LocalModel) -> ModelRow.State {
        if let progress = model.downloads[local] { return .downloading(progress) }
        if model.loading.contains(local) { return .loading }
        return local.isDownloaded ? .ready : .notDownloaded
    }

    /**
     Asks before removing, because these are gigabytes and the cache is shared
     with every other MLX app on this machine. Says where the files go, so the
     answer is an informed one rather than a guess about how final this is.
     */
    private func confirmRemoval(of local: LocalModel) {
        let alert = NSAlert()
        alert.messageText = "Remove \(local.displayName)?"
        alert.informativeText = """
        Its \(local.approximateSize) of weights are moved to the Trash. Other apps \
        sharing the Hugging Face cache lose them too, and downloading again is \
        the only way back.
        """
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try model.remove(local)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = "Could not remove \(local.displayName)"
            failure.runModal()
        }
    }
}

/** One model: what it is, whether it is here, and whether it is the default. */
private struct ModelRow: View {
    enum State: Equatable {
        case ready
        case notDownloaded
        case downloading(Double)
        /** On disk, being read into memory. Seconds, not minutes, and no bar. */
        case loading
    }

    let title: String
    let detail: String
    let isDefault: Bool
    let isTuned: Bool
    let onMakeDefault: () -> Void
    let state: State
    var onDownload: (() -> Void)?
    var onCancel: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            /**
             A radio rather than a checkmark, because exactly one model is the
             default and a checkbox would suggest otherwise.
             */
            Image(systemName: isDefault ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(isDefault ? Color.accentColor : .secondary)
                .onTapGesture { if isSelectable { onMakeDefault() } }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch state {
            case .downloading(let progress):
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 110)
                Button("Stop") { onCancel?() }

            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text("Loading…")
                    .font(.callout)
                    .foregroundStyle(.secondary)

            case .notDownloaded:
                Button("Download") { onDownload?() }

            case .ready:
                /**
                 Nothing where the button would be for Apple's model, which has
                 no files of its own to remove.
                 */
                if let onRemove {
                    Button("Remove", action: onRemove)
                }
            }
        }
        .padding(.horizontal, SettingsRow.horizontalPadding)
        .padding(.vertical, SettingsRow.verticalPadding)
        .contentShape(Rectangle())
        .onTapGesture { if isSelectable { onMakeDefault() } }
    }

    /** Choosing weights that are not here yet would fail on the next keystroke. */
    private var isSelectable: Bool { state == .ready }
}
