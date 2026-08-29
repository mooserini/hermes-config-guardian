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
                } else if model.maintenance != nil && !model.maintenanceReviewReady {
                    maintenanceActiveView
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
                Menu {
                    Toggle("Play attention sound", isOn: $model.attentionSoundEnabled)
                    Toggle("Open window automatically", isOn: $model.attentionWindowEnabled)
                    Divider()
                    Toggle(
                        "Launch at login",
                        isOn: Binding(
                            get: { model.launchAtLoginEnabled },
                            set: { model.setLaunchAtLogin($0) }
                        )
                    )
                    if let message = model.launchAtLoginMessage {
                        Text(message)
                    }
                    if model.launchAtLoginNeedsApproval {
                        Button("Open Login Items Settings") {
                            model.openLoginItemsSettings()
                        }
                    }
                } label: {
                    Label("Attention", systemImage: "bell")
                }
                .help("Choose how Guardian gets your attention when the watched file changes")
                .accessibilityLabel("Attention settings")
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
        .onAppear { model.refreshLaunchAtLoginStatus() }
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
        VStack(alignment: .leading, spacing: 10) {
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
            if let message = model.maintenanceMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("Begin Hermes update") { model.beginHermesUpdate() }
                .buttonStyle(.bordered)
                .help("Seal the current approved configuration before intentionally updating Hermes")
                .accessibilityHint("Begins a durable maintenance window without approving later changes")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var maintenanceActiveView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let maintenance = model.maintenance {
                Label("Maintenance active", systemImage: "wrench.and.screwdriver.fill")
                    .font(.headline)
                    .foregroundStyle(.blue)
                Text("Started \(maintenance.manifest.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Guardian sealed the exact approved configuration and is recording distinct rewrites without repeatedly interrupting you.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(model.maintenanceObservedCount) distinct intermediate proposal\(model.maintenanceObservedCount == 1 ? "" : "s") observed")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)

                if case .invalid = model.status {
                    Label("The current file is invalid YAML. The pre-update checkpoint remains intact.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("End update and review") { model.endHermesUpdateAndReview() }
                    .buttonStyle(.borderedProminent)
                    .help("Compare the final stable file with the sealed pre-update checkpoint")
                    .accessibilityHint("Opens a final review without automatically accepting the result")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func maintenanceReviewBanner(_ maintenance: MaintenanceWindow) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("Final update review", systemImage: "checkmark.seal")
                .font(.subheadline.weight(.semibold))
            Text("\(model.maintenanceObservedCount) distinct intermediate proposal\(model.maintenanceObservedCount == 1 ? "" : "s") observed since \(maintenance.manifest.startedAt.formatted(date: .abbreviated, time: .shortened)). Nothing has been approved automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Label("Reject restores the exact pre-update bytes. The updated Hermes version may require a newer configuration schema; Guardian has not proven runtime compatibility.", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private func pendingView(_ pending: PendingChange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let maintenance = model.maintenance {
                maintenanceReviewBanner(maintenance)
            }
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
                    if model.maintenance != nil {
                        keepReviewingButton
                    }
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

            if model.reviewExpanded && pending.validationError == nil && model.maintenance == nil {
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
                if model.maintenance != nil {
                    keepReviewingButton
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    acceptButton
                    reviewButton
                    clarifyButton
                }
                HStack(spacing: 8) {
                    rejectButton
                    if model.maintenance != nil {
                        keepReviewingButton
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Configuration decision")
    }

    private var acceptButton: some View {
        Button(model.maintenance == nil ? "Accept" : "Accept final version") { model.accept() }
            .buttonStyle(.borderedProminent)
            .help("Accept this proposal and make it the approved snapshot")
            .accessibilityLabel(model.maintenance == nil ? "Accept" : "Accept final version")
            .accessibilityHint(model.maintenance == nil
                               ? "Makes the current proposal the approved snapshot"
                               : "Ends maintenance and makes only the final version the approved snapshot")
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
        Button(model.maintenance == nil ? "Reject" : "Reject and restore checkpoint", role: .destructive) { model.reject() }
            .buttonStyle(.bordered)
            .help("Reject this change and restore the approved version")
            .accessibilityLabel(model.maintenance == nil ? "Reject" : "Reject and restore checkpoint")
            .accessibilityHint(model.maintenance == nil
                               ? "Discards the unapproved proposal and restores the last approved snapshot"
                               : "Discards the final update result and restores the exact pre-update checkpoint")
    }

    private var keepReviewingButton: some View {
        Button("Keep updating") { model.keepMaintenanceActive() }
            .buttonStyle(.bordered)
            .help("Return to maintenance mode without accepting or restoring any file")
            .accessibilityHint("Leaves the maintenance checkpoint active and makes no file change")
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
                if let warning = TypeTransitionGuard.reviewWarning(for: pending.changes) {
                    Label {
                        Text(warning)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Value type changed")
                }
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
        case .maintenance: return .blue
        case .changed: return .orange
        case .invalid, .error: return .red
        case .unenrolled: return .secondary
        }
    }
}
