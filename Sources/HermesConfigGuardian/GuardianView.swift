import GuardianCore
import SwiftUI

struct GuardianView: View {
    @ObservedObject var model: GuardianModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()

            if model.approved == nil {
                enrollment
            } else if let pending = model.pending {
                pendingView(pending)
            } else {
                cleanView
            }

            if case let .error(message) = model.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Divider()
            HStack {
                Button("Check now") { model.checkForChange() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(16)
        .frame(width: 440)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: model.status.symbol)
                .font(.title2)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title).font(.headline)
                Text(model.sourceURL.path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var enrollment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Guardian will validate this YAML and preserve an independently verified approved snapshot. Nothing is accepted automatically.")
                .font(.subheadline)
            Button("Enroll current configuration") { model.enroll() }
                .buttonStyle(.borderedProminent)
        }
    }

    private var cleanView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The file matches its approved snapshot.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if let manifest = model.approved?.manifest {
                Text("Approved \(manifest.approvedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Fingerprint \(manifest.approvedHash.prefix(16))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func pendingView(_ pending: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationError = pending.validationError {
                Text("The changed file cannot be accepted because it is invalid:")
                    .font(.subheadline.weight(.semibold))
                Text(validationError)
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("The file no longer matches the version you approved.")
                    .font(.subheadline)

                HStack {
                    Button("Accept") { model.accept() }
                        .buttonStyle(.borderedProminent)
                    Button("Review") { model.reviewExpanded.toggle() }
                        .buttonStyle(.bordered)
                    Button("Clarify") { model.clarify() }
                        .buttonStyle(.bordered)
                        .disabled(model.isClarifying)
                    Button("Reject", role: .destructive) { model.reject() }
                        .buttonStyle(.bordered)
                        .help("Reject this change and restore the approved version")
                }
            }

            if model.isClarifying {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Retrieving official documentation and preparing explanation…")
                }
                    .font(.caption)
            }

            if let explanation = model.explanation {
                VStack(alignment: .leading, spacing: 6) {
                    Text("On-device explanation")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(explanation)
                        .font(.callout)
                        .textSelection(.enabled)
                }
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            if let documentationStatus = model.documentationStatus {
                documentationEvidence(status: documentationStatus)
            }

            if model.reviewExpanded || pending.validationError != nil {
                review(pending)
            }
        }
    }

    private func documentationEvidence(status: String) -> some View {
        DisclosureGroup(isExpanded: $model.documentationExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let warning = model.documentationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                ForEach(model.documentationExcerpts.prefix(4)) { excerpt in
                    VStack(alignment: .leading, spacing: 3) {
                        Link(destination: excerpt.sourceURL) {
                            Label("\(excerpt.origin.label): \(excerpt.settingPath)", systemImage: "arrow.up.right.square")
                        }
                        .font(.caption.weight(.semibold))
                        Text(excerpt.text)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Official documentation evidence")
        }
        .font(.caption.weight(.semibold))
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func review(_ pending: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !pending.changes.isEmpty {
                Text("Meaningful changes").font(.subheadline.weight(.semibold))
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 9) {
                        ForEach(pending.changes) { change in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(change.path).font(.caption.monospaced().weight(.semibold))
                                Text(changeSummary(change))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            Button("Restore approved version", role: .destructive) { model.restore() }
                .buttonStyle(.bordered)
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func changeSummary(_ change: SemanticChange) -> String {
        switch change.kind {
        case .added: return "Added: \(change.after ?? "")"
        case .removed: return "Removed: \(change.before ?? "")"
        case .changed: return "\(change.before ?? "") → \(change.after ?? "")"
        }
    }

    private var statusColor: Color {
        switch model.status {
        case .clean: return .green
        case .changed: return .orange
        case .invalid, .error: return .red
        case .unenrolled: return .secondary
        }
    }
}
