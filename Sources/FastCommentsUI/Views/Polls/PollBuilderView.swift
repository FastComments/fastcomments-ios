import SwiftUI
import FastCommentsSwift

/// Writes a `PollDraft` inside the comment input. Mirrors the web widget's poll editing card.
struct PollBuilderView: View {
    @Binding var draft: PollDraft
    @Binding var error: PollDraft.ValidationError?
    /// Bumped to move focus back to the question, when the toolbar's poll button is tapped with the builder open.
    let questionFocusRequest: Int
    let onRemove: () -> Void

    private enum Field: Hashable {
        case question
        case option(UUID)
    }

    private static let errorAnchor = "poll-builder-error-anchor"

    @Environment(\.fastCommentsTheme) private var theme
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @FocusState private var focus: Field?
    @State private var contentHeight: CGFloat = 0
    @ScaledMetric(relativeTo: .subheadline) private var scaledMaxHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .subheadline) private var markSize = PollStyle.markSize

    /// The builder scrolls once it would crowd out the input row and the keyboard.
    private var maxHeight: CGFloat {
        verticalSizeClass == .compact ? 120 : min(scaledMaxHeight, 340)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .padding(.bottom, 12)
                    .background(
                        GeometryReader { geometry in
                            Color.clear.preference(key: PollBuilderHeightKey.self, value: geometry.size.height)
                        }
                    )
            }
            .frame(height: min(contentHeight, maxHeight))
            .onPreferenceChange(PollBuilderHeightKey.self) { contentHeight = $0 }
            .onChange(of: focus) { field in
                guard let field else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(field, anchor: .center) }
            }
            .onChange(of: error) { newError in
                // The builder scrolls inside the composer, so bring the error into view or it can go unseen.
                guard let newError else { return }
                PollStyle.announce(newError.message)
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.errorAnchor, anchor: .bottom) }
            }
        }
        // A hop to the next main actor turn: the comment field still holds first responder while this view appears.
        .task { focus = .question }
        .onChange(of: questionFocusRequest) { _ in focus = .question }
        .onChange(of: draft) { newDraft in
            handleDraftChange(newDraft)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            questionField
                .padding(.bottom, 2)

            ForEach(Array(draft.options.enumerated()), id: \.element.id) { index, option in
                optionRow(option, index: index)
                    .id(Field.option(option.id))
            }

            if draft.canAddOption {
                addOptionRow
            }

            durationPicker
                .padding(.top, 4)

            Toggle(isOn: $draft.requireVoteToSeeResults) {
                Text(NSLocalizedString("poll_require_vote_to_see_results", bundle: .module, comment: ""))
                    .font(.footnote)
            }
            .tint(theme.resolvePollAccentColor())
            .accessibilityIdentifier("poll-builder-require-vote")

            privacyRow

            if let error {
                Text(error.message)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.resolvePollDangerColor())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("poll-builder-error")
            }

            PollLinkButton(
                title: NSLocalizedString("poll_remove", bundle: .module, comment: ""),
                identifier: "poll-builder-remove",
                color: theme.resolvePollDangerColor(),
                action: onRemove
            )
            .id(Self.errorAnchor)
        }
    }

    // MARK: - Question

    private var questionField: some View {
        TextField(
            NSLocalizedString("poll_question_placeholder", bundle: .module, comment: ""),
            text: $draft.question,
            axis: .vertical
        )
        .font(theme.resolveBodyFont().weight(.semibold))
        .lineLimit(1...3)
        .submitLabel(.next)
        .focused($focus, equals: .question)
        .id(Field.question)
        .accessibilityIdentifier("poll-builder-question")
    }

    // MARK: - Options

    private func optionRow(_ option: PollDraft.Option, index: Int) -> some View {
        let shape = PollStyle.shape(radius: PollStyle.optionRadius)
        let isFocused = focus == .option(option.id)

        return HStack(spacing: 12) {
            PollStyle.shape(radius: PollStyle.markRadius)
                .strokeBorder(theme.resolvePollBorderColor(), lineWidth: 1)
                .frame(width: markSize, height: markSize)
                .accessibilityHidden(true)

            TextField(
                String(
                    format: NSLocalizedString("poll_option_placeholder_%lld", bundle: .module, comment: ""), index + 1),
                text: optionText(id: option.id)
            )
            .font(theme.resolveBodyFont().weight(.medium))
            .submitLabel(index == draft.options.count - 1 && !draft.canAddOption ? .done : .next)
            .focused($focus, equals: .option(option.id))
            .onSubmit { advanceFocus(from: index) }
            .accessibilityIdentifier("poll-builder-option-\(index)")

            if draft.canRemoveOption {
                Button {
                    removeOption(id: option.id, at: index)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("poll_remove_option", bundle: .module, comment: ""))
                .accessibilityIdentifier("poll-builder-remove-option-\(index)")
            }
        }
        .padding(.leading, 12)
        .frame(minHeight: 44)
        .background(theme.resolvePollOptionBackgroundColor())
        .clipShape(shape)
        .overlay(shape.strokeBorder(isFocused ? theme.resolvePollAccentColor() : Color.clear, lineWidth: 1))
    }

    private var addOptionRow: some View {
        let shape = PollStyle.shape(radius: PollStyle.optionRadius)
        let dashed = StrokeStyle(lineWidth: 1, dash: [4, 3])

        return Button {
            addOption()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    PollStyle.shape(radius: PollStyle.markRadius)
                        .stroke(theme.resolvePollBorderColor(), style: dashed)
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                }
                .frame(width: markSize, height: markSize)

                Text(NSLocalizedString("poll_add_option", bundle: .module, comment: ""))
                    .font(theme.resolveBodyFont().weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .overlay(shape.stroke(theme.resolvePollBorderColor(), style: dashed))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("poll-builder-add-option")
    }

    // MARK: - Duration

    private var durationPicker: some View {
        PollFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(PollDraft.closesDaysChoices, id: \.self) { days in
                durationPill(days: days)
            }
        }
    }

    private func durationPill(days: Int) -> some View {
        let isChosen = draft.closesDays == days

        return Button {
            draft.closesDays = days
        } label: {
            Text(Self.durationLabel(days: days))
                .font(.footnote)
                .foregroundStyle(isChosen ? theme.resolvePollAccentTextColor() : Color.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(Capsule().fill(isChosen ? theme.resolvePollAccentColor() : Color.clear))
                .overlay(Capsule().strokeBorder(isChosen ? Color.clear : theme.resolvePollBorderColor(), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityIdentifier("poll-builder-duration-\(days)")
    }

    private static func durationLabel(days: Int) -> String {
        switch days {
        case 1: return NSLocalizedString("poll_closes_1_day", bundle: .module, comment: "")
        case 3: return NSLocalizedString("poll_closes_3_days", bundle: .module, comment: "")
        case 7: return NSLocalizedString("poll_closes_1_week", bundle: .module, comment: "")
        default: return NSLocalizedString("poll_closes_never", bundle: .module, comment: "")
        }
    }

    // MARK: - Privacy

    private var privacyRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(NSLocalizedString("poll_privacy_label", bundle: .module, comment: ""))
                    .font(.footnote)

                Spacer()

                Menu {
                    Picker(
                        NSLocalizedString("poll_privacy_label", bundle: .module, comment: ""),
                        selection: $draft.privacy
                    ) {
                        ForEach(PollPrivacy.allCases, id: \.self) { privacy in
                            Text(Self.privacyLabel(privacy)).tag(privacy)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(Self.privacyLabel(draft.privacy))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .accessibilityHidden(true)
                    }
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(theme.resolvePollBorderColor(), lineWidth: 1))
                }
                .tint(.primary)
                .accessibilityLabel(NSLocalizedString("poll_privacy_label", bundle: .module, comment: ""))
                .accessibilityValue(Self.privacyLabel(draft.privacy))
                .accessibilityIdentifier("poll-builder-privacy")
            }

            // The web shows this as a hover tooltip, which a phone doesn't have.
            if draft.privacy == ._2 {
                Text(NSLocalizedString("poll_privacy_help", bundle: .module, comment: ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func privacyLabel(_ privacy: PollPrivacy) -> String {
        switch privacy {
        case ._0: return NSLocalizedString("poll_privacy_anonymous", bundle: .module, comment: "")
        case ._1: return NSLocalizedString("poll_privacy_admins", bundle: .module, comment: "")
        case ._2: return NSLocalizedString("poll_privacy_public", bundle: .module, comment: "")
        }
    }

    // MARK: - Editing

    /// Looked up by id, not index: a binding into the array can outlive its row when an option is removed.
    private func optionText(id: UUID) -> Binding<String> {
        Binding(
            get: { draft.options.first { $0.id == id }?.text ?? "" },
            set: { newText in
                guard let index = draft.options.firstIndex(where: { $0.id == id }) else { return }
                draft.options[index].text = newText
            }
        )
    }

    /// Clearing the error and limiting the text happen here rather than in the field bindings: a TextField only redraws
    /// a trimmed value if its state actually changed, so the longer value has to land first.
    private func handleDraftChange(_ newDraft: PollDraft) {
        error = nil

        // A multi-line field gets its return key as a newline rather than a submit.
        if newDraft.question.hasSuffix("\n") {
            advanceFocus(from: -1)
        }

        var cleaned = newDraft
        cleaned.question = PollDraft.sanitize(
            newDraft.question.trimmingCharacters(in: .newlines), maxLength: PollDraft.maxQuestionLength)
        for index in cleaned.options.indices {
            cleaned.options[index].text = PollDraft.sanitize(
                cleaned.options[index].text, maxLength: PollDraft.maxOptionLength)
        }
        if cleaned != newDraft {
            draft = cleaned
        }
    }

    private func addOption() {
        guard draft.canAddOption else { return }
        let option = PollDraft.Option()
        draft.options.append(option)
        focus = .option(option.id)
    }

    private func removeOption(id: UUID, at index: Int) {
        guard draft.canRemoveOption else { return }
        draft.options.removeAll { $0.id == id }
        focus = .option(draft.options[max(0, index - 1)].id)
    }

    private func advanceFocus(from index: Int) {
        let next = index + 1
        if draft.options.indices.contains(next) {
            focus = .option(draft.options[next].id)
        } else if draft.canAddOption {
            addOption()
        } else {
            focus = nil
        }
    }
}

private struct PollBuilderHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
