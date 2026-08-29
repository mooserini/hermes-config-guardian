import GuardianCore
import SwiftUI

struct GuardianView: View {
    @ObservedObject var model: GuardianModel
    var onOpenWindow: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            Group {
                if model.approved == nil {
                    enrollment
                } else if let pending = model.pending {
                    pendingView(pending)
                } else {
                    cleanView
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            if case let .error(message) = model.status {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Guardian error")
                    .accessibilityValue(message)
            }

            Divider()

            HStack {
                Button("Check now") { model.checkForChange() }
                    .help("Re-read the watched file and compare it with the approved snapshot")
                    .accessibilityHint("Compares the watched file with the approved snapshot")
                if let onOpenWindow {
                    Button("Open window") { onOpenWindow() }
                        .help("Open Guardian in a resizable window")
                        .accessibilityHint("Opens the same Guardian state in a resizable window")
                }
                Spacer(minLength: 8)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .help("Quit Hermes Config Guardian")
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(
            minWidth: 360,
            idealWidth: 440,
            maxWidth: .infinity,
            minHeight: 360,
            idealHeight: 520,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.status.symbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.status.title)
                    .font(.headline)
                Text(model.sourceURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.sourceURL.path)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var enrollment: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Guardian will validate this YAML and preserve an independently verified approved snapshot. Nothing is accepted automatically.")
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Enroll current configuration") { model.enroll() }
                .buttonStyle(.borderedProminent)
                .help("Validate the current file and store it as the approved snapshot")
                .accessibilityHint("Stores the current file as the approved snapshot. Nothing is accepted automatically.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cleanView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("The file matches its approved snapshot.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
            if let manifest = model.approved?.manifest {
                Text("Approved \(manifest.approvedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Fingerprint \(manifest.approvedHash.prefix(16))…")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help("SHA-256 fingerprint of the approved snapshot")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func pendingView(_ pending: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let validationError = pending.validationError {
                VStack(alignment: .leading, spacing: 6) {
                    Text("The changed file cannot be accepted because it is invalid:")
                        .font(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)

                HStack(spacing: 8) {
                    clarifyButton
                    rejectButton
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Invalid configuration decision")
            } else {
                Text("The file no longer matches the version you approved.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                decisionBar
            }

            if model.isClarifying {
                HStack(alignment: .center, spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(pending.validationError == nil
                         ? "Retrieving official documentation and preparing explanation…"
                         : "Preparing a safe explanation of the invalid text…")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(pending.validationError == nil
                                    ? "Retrieving official documentation and preparing explanation"
                                    : "Preparing a safe explanation of the invalid text")
            }

            detailsScroll(pending)

            if model.reviewExpanded && pending.validationError == nil {
                Button("Restore approved version", role: .destructive) { model.restore() }
                    .buttonStyle(.bordered)
                    .help("Write the last approved snapshot back to the watched file")
                    .accessibilityHint("Replaces the watched file with the last approved snapshot. This does not record a rejection receipt.")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var decisionBar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                acceptButton
                reviewButton
                clarifyButton
                rejectButton
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    acceptButton
                    reviewButton
                    clarifyButton
                }
                rejectButton
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configuration decision")
    }

    private var acceptButton: some View {
        Button("Accept") { model.accept() }
            .buttonStyle(.borderedProminent)
            .help("Accept this proposal and make it the approved snapshot")
            .accessibilityLabel("Accept")
            .accessibilityHint("Makes the current proposal the approved snapshot")
    }

    private var reviewButton: some View {
        Button("Review") { model.reviewExpanded.toggle() }
            .buttonStyle(.bordered)
            .help(model.reviewExpanded
                  ? "Hide the list of meaningful changes"
                  : "Show the list of meaningful changes")
            .accessibilityLabel("Review")
            .accessibilityValue(model.reviewExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows or hides the list of meaningful configuration changes")
            .accessibilityAddTraits(model.reviewExpanded ? .isSelected : [])
    }

    private var clarifyButton: some View {
        Button("Clarify") { model.clarify() }
            .buttonStyle(.bordered)
            .disabled(model.isClarifying)
            .help(model.pending?.validationError == nil
                  ? "Explain these changes from official documentation"
                  : "Explain why the text is invalid and briefly respond to the redacted offending fragment")
            .accessibilityLabel("Clarify")
            .accessibilityHint(model.pending?.validationError == nil
                               ? "Retrieves official documentation and prepares an explanation of the proposed changes"
                               : "Prepares a safe explanation of the invalid configuration text")
    }

    private var rejectButton: some View {
        Button("Reject", role: .destructive) { model.reject() }
            .buttonStyle(.bordered)
            .help("Reject this change and restore the approved version")
            .accessibilityLabel("Reject")
            .accessibilityHint("Discards the unapproved proposal and restores the last approved snapshot")
    }

    @ViewBuilder
    private func detailsScroll(_ pending: PendingChange) -> some View {
        let showsReview = model.reviewExpanded && pending.validationError == nil
        let showsInvalidFragment = pending.validationError != nil && pending.invalidFragment != nil
        let showsExplanation = model.explanation != nil
        let showsDocumentation = model.documentationStatus != nil
        let hasDetails = showsReview || showsInvalidFragment || showsExplanation || showsDocumentation

        if hasDetails {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let explanation = model.explanation {
                        explanationCard(explanation)
                    }

                    if let documentationStatus = model.documentationStatus {
                        documentationEvidence(status: documentationStatus)
                    }

                    if showsInvalidFragment, let fragment = pending.invalidFragment {
                        invalidFragmentCard(fragment)
                    }

                    if showsReview {
                        review(pending)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .padding(.trailing, 2)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, minHeight: 72, maxHeight: .infinity, alignment: .topLeading)
            .layoutPriority(1)
            .accessibilityLabel("Change details")
        } else {
            Spacer(minLength: 0)
        }
    }

    private func invalidFragmentCard(_ fragment: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Unparsed text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(fragment)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Unparsed invalid text")
        .accessibilityValue(fragment)
    }

    private func explanationCard(_ explanation: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.clarificationSource?.title ?? "Grounded explanation")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(explanation)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.clarificationSource?.title ?? "Grounded explanation")
        .accessibilityValue(explanation)
    }

    private func documentationEvidence(status: String) -> some View {
        DisclosureGroup(isExpanded: $model.documentationExpanded) {
            VStack(alignment: .leading, spacing: 9) {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let warning = model.documentationWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Official documentation evidence")
        }
        .font(.caption.weight(.semibold))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func review(_ pending: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if pending.changes.isEmpty {
                Text("No meaningful semantic changes were detected in the YAML mapping, but the file bytes no longer match the approved snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Meaningful changes")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(pending.changes) { change in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(changeKindLabel(change.kind))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(change.path)
                                    .font(.caption.monospaced().weight(.semibold))
                                    .textSelection(.enabled)
                            }
                            Text(changeSummary(change))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(changeKindLabel(change.kind)) \(change.path)")
                        .accessibilityValue(changeSummary(change))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Meaningful changes")
    }

    private func changeKindLabel(_ kind: ChangeKind) -> String {
        switch kind {
        case .added: return "Added"
        case .removed: return "Removed"
        case .changed: return "Changed"
        }
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
