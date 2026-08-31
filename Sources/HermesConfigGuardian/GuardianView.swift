import AppKit
import GuardianCore
import SwiftUI

struct GuardianView: View {
    @ObservedObject var model: GuardianModel
    var onOpenWindow: (() -> Void)?
    @State private var showMaintenanceConfirmation = false
    @State private var showRecordSkillsBaseline = false
    @State private var showPendingSkillsReview = false

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
                    .disabled(model.approved == nil)
                    .help(model.approved == nil
                          ? "Enroll a configuration before checking for changes"
                          : "Re-read the watched file and compare it with the approved snapshot")
                    .accessibilityHint(model.approved == nil
                                       ? "Unavailable until a configuration is enrolled"
                                       : "Compares the watched file with the approved snapshot")
                moreMenu
                Spacer(minLength: 8)
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .help("Quit Hermes Guardian")
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
        .confirmationDialog(
            "Start update maintenance?",
            isPresented: $showMaintenanceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Start maintenance") { model.beginHermesUpdate() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Guardian will seal the currently approved configuration, group expected Hermes update writes, preserve every observed proposal, and require final approval before the snapshot advances.")
        }
        .confirmationDialog(
            "Record current skill state?",
            isPresented: $showRecordSkillsBaseline,
            titleVisibility: .visible
        ) {
            Button("Record current skill state") { model.recordCurrentSkillState() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stores a local integrity baseline of the current skill files. It does not approve pending skill writes or change any skill file.")
        }
        .sheet(isPresented: $showPendingSkillsReview) {
            PendingSkillsReviewSheet(proposals: model.pendingSkillProposals)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: model.headlineSymbol)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline)
                    .font(.headline)
                Text(model.approved == nil ? model.sourceURL.path : model.monitoringSummary)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("MONITORED FILES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                monitoredFileRow

                Text("SKILL STATE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                pendingSkillsRow
                skillsIntegrityRow

                Divider()

                notificationsSection

                Divider()

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTO-APPROVAL")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("0 exact rules · Automatic approval is not enabled")
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let manifest = model.approved?.manifest {
                    Text("Approved \(manifest.approvedAt.formatted(date: .abbreviated, time: .shortened)) · fingerprint \(manifest.approvedHash.prefix(12))…")
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var monitoredFileRow: some View {
        if let onOpenWindow {
            Button(action: onOpenWindow) {
                monitoredFileRowContent
            }
            .buttonStyle(.plain)
            .help("Open this file in Guardian's resizable window")
            .accessibilityLabel("Open monitored file \(model.sourceURL.lastPathComponent) in window")
            .accessibilityHint("Opens the full Guardian window with this file's history, receipts, and review details")
            .accessibilityValue("Approved")
        } else {
            monitoredFileRowContent
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Monitored file \(model.sourceURL.lastPathComponent)")
                .accessibilityValue("Approved")
        }
    }

    private var monitoredFileRowContent: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.sourceURL.lastPathComponent)
                    .font(.subheadline.weight(.semibold))
                Text(model.sourceURL.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.sourceURL.path)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text("Approved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                if onOpenWindow != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var pendingSkillsRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: model.pendingSkills.needsAttention ? "tray.full.fill" : "tray")
                    .foregroundStyle(model.pendingSkills.needsAttention ? Color.orange : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pending skills")
                        .font(.subheadline.weight(.semibold))
                    Text(pendingSkillsDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(model.pendingSkills.needsAttention ? "Awaiting review" : "None")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.pendingSkills.needsAttention ? Color.orange : Color.secondary)
            }

            if model.pendingSkills.needsAttention {
                Button("Review") { showPendingSkillsReview = true }
                    .buttonStyle(.bordered)
                    .help("Read the queued skill proposals and copy an ID for Hermes' own review commands")
                    .accessibilityHint("Opens a read-only list of pending skill proposals")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pending skills")
        .accessibilityValue(pendingSkillsDetail)
    }

    private var pendingSkillsDetail: String {
        switch model.pendingSkills {
        case .none:
            return "none"
        case let .awaitingReview(count):
            return "\(count) awaiting review"
        case let .unavailable(message):
            return message
        }
    }

    @ViewBuilder
    private var skillsIntegrityRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: skillsIntegritySymbol)
                    .foregroundStyle(skillsIntegrityColor)
                    .symbolRenderingMode(.hierarchical)
                    .font(.title3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Skills integrity")
                        .font(.subheadline.weight(.semibold))
                    Text(skillsIntegrityDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Text(skillsIntegrityBadge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(skillsIntegrityColor)
            }

            if onOpenWindow == nil, let drift = model.skillsIntegrity.drift {
                skillsDriftDetails(drift)
            }

            if model.canRecordSkillsBaseline {
                Button("Record current skill state") {
                    if model.skillsIntegrity.drift != nil {
                        showRecordSkillsBaseline = true
                    } else {
                        model.recordCurrentSkillState()
                    }
                }
                .buttonStyle(.bordered)
                .help("Stores a local integrity baseline. This does not approve pending skill writes or change any skill files.")
                .accessibilityHint("Stores only local Guardian state. It does not approve pending skill writes or change skills.")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Skills integrity")
        .accessibilityValue(model.skillsIntegrity.displayText)
    }

    private func skillsDriftDetails(_ drift: SkillsDrift) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !drift.added.isEmpty {
                Text("Added: \(drift.added.joined(separator: ", "))")
            }
            if !drift.changed.isEmpty {
                Text("Changed: \(drift.changed.joined(separator: ", "))")
            }
            if !drift.removed.isEmpty {
                Text("Removed: \(drift.removed.joined(separator: ", "))")
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Skills integrity drift paths")
    }

    private var skillsIntegritySymbol: String {
        switch model.skillsIntegrity {
        case .clean:
            return "folder.badge.checkmark"
        case .baselineNotRecorded:
            return "folder.badge.questionmark"
        case .drifted:
            return "folder.badge.questionmark"
        case .unavailable:
            return "folder.badge.minus"
        }
    }

    private var skillsIntegrityColor: Color {
        switch model.skillsIntegrity {
        case .clean:
            return .green
        case .baselineNotRecorded:
            return .secondary
        case .drifted:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var skillsIntegrityBadge: String {
        switch model.skillsIntegrity {
        case .clean:
            return "Matches"
        case .baselineNotRecorded:
            return "Not recorded"
        case let .drifted(drift):
            return "\(drift.totalCount) differ"
        case .unavailable:
            return "Unavailable"
        }
    }

    private var skillsIntegrityDetail: String {
        switch model.skillsIntegrity {
        case .clean:
            return "matches recorded baseline"
        case .baselineNotRecorded:
            return "baseline not recorded"
        case let .drifted(drift):
            return "\(drift.totalCount) file\(drift.totalCount == 1 ? "" : "s") differ"
        case let .unavailable(message):
            return message
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NOTIFICATIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Toggle("Open review window automatically", isOn: $model.attentionWindowEnabled)
                .help("Open Guardian for a new proposal or a still-pending skill review at login")
            Toggle("Play attention sound", isOn: $model.attentionSoundEnabled)
                .help("Play a sound when a newly proposed file version needs a decision")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var moreMenu: some View {
        Menu {
            if model.approved != nil, model.pending == nil, model.maintenance == nil {
                Button("Update maintenance…") {
                    showMaintenanceConfirmation = true
                }
                Divider()
            }
            appBehaviorMenu
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .help("Exceptional Guardian actions and app behavior")
        .accessibilityLabel("More Guardian actions")
    }

    private var appBehaviorMenu: some View {
        Menu {
            Toggle(
                "Launch at login",
                isOn: Binding(
                    get: { model.launchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            if let message = model.launchAtLoginMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.launchAtLoginNeedsApproval {
                Button("Open Login Items Settings") {
                    model.openLoginItemsSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        } label: {
            Label("App Behavior", systemImage: "gearshape")
        }
        .help("Guardian behavior that is not a notification or approval rule")
        .accessibilityLabel("Guardian app behavior")
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
        case .clean:
            if model.pendingSkills.needsAttention || model.skillsIntegrity.needsAttention {
                return .orange
            }
            return .green
        case .maintenance: return .blue
        case .changed: return .orange
        case .invalid, .error: return .red
        case .unenrolled: return .secondary
        }
    }
}

private struct PendingSkillsReviewSheet: View {
    let proposals: [PendingSkillProposal]
    @Environment(\.dismiss) private var dismiss
    @State private var copiedID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Pending skills")
                    .font(.headline)
                Text("Read-only review. Hermes remains responsible for approving or rejecting a proposal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if proposals.isEmpty {
                Text("There are no pending skill records to review.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(proposals) { proposal in
                            proposalCard(proposal)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
            }
        }
        .padding(18)
        .frame(minWidth: 440, idealWidth: 560, minHeight: 360, idealHeight: 560)
    }

    private func proposalCard(_ proposal: PendingSkillProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title)
                .font(.subheadline.weight(.semibold))
                .textSelection(.enabled)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(proposal.id)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                Button(copiedID == proposal.id ? "Copied" : "Copy ID") {
                    copy(proposal.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy this pending proposal's Hermes ID")
                Spacer(minLength: 0)
            }

            Text("\(proposal.action) · \(proposal.origin)" + createdText(for: proposal))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let issue = proposal.issue {
                Text(issue)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let recordText = proposal.recordText {
                Text(recordText)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    private func createdText(for proposal: PendingSkillProposal) -> String {
        guard let createdAt = proposal.createdAt else { return "" }
        return " · staged \(createdAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func copy(_ id: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(id, forType: .string) else { return }
        copiedID = id
    }
}
