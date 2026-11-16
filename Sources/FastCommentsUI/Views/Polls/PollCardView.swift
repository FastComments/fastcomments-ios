import SwiftUI
import FastCommentsSwift
#if canImport(UIKit)
    import UIKit
#endif

/// Renders a comment's poll the same way the web widget's polls extension does: each option is a chip that doubles
/// as its own result bar once results are showing.
struct PollCardView: View {
    @ObservedObject var comment: RenderableComment
    let sdk: FastCommentsSDK

    @Environment(\.fastCommentsTheme) private var theme
    @State private var showVoters = false

    var body: some View {
        if let poll = comment.comment.poll {
            card(for: poll)
                .sheet(isPresented: $showVoters) {
                    PollVotersSheet(sdk: sdk, commentId: commentId)
                        .environment(\.fastCommentsTheme, theme)
                }
        }
    }

    private var commentId: String { comment.comment.id }

    private func card(for poll: CommentPoll) -> some View {
        let results = PollRules.isShowingResults(comment.comment, showResultsOverride: comment.pollShowResults)
        let closed = PollRules.isClosed(poll)

        return VStack(alignment: .leading, spacing: 10) {
            Text(PollRules.plainText(fromEscaped: poll.question))
                .font(theme.resolveBodyFont().weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("poll-question-\(commentId)")

            VStack(spacing: 8) {
                ForEach(Array(poll.options.enumerated()), id: \.element.id) { index, option in
                    PollOptionRow(
                        label: PollRules.plainText(fromEscaped: option.label),
                        percent: PollRules.percent(votes: option.votes, total: poll.totalVotes),
                        isSelected: PollRules.isSelected(comment.comment, optionId: option.id),
                        showsResults: results,
                        isClosed: closed,
                        action: { select(optionId: option.id) }
                    )
                    .accessibilityIdentifier("poll-option-\(commentId)-\(index)")
                }
            }
            .opacity(comment.pollSaving ? 0.6 : 1)
            .allowsHitTesting(!comment.pollSaving)
            .animation(.easeOut(duration: 0.18), value: comment.pollSaving)

            infoFooter(for: poll, closed: closed)

            if let error = comment.pollError {
                Text(error)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.resolvePollDangerColor())
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("poll-error-\(commentId)")
            }

            actionFooter(for: poll, results: results, closed: closed)
        }
        .padding(.top, 4)
        .onChange(of: comment.pollError) { error in
            if let error { PollStyle.announce(error) }
        }
    }

    private func select(optionId: String) {
        Task {
            await sdk.selectPollOption(commentId: commentId, optionId: optionId)
            #if canImport(UIKit)
                if comment.pollError == nil {
                    UISelectionFeedbackGenerator().selectionChanged()
                }
            #endif
        }
    }

    private func infoFooter(for poll: CommentPoll, closed: Bool) -> some View {
        PollFlowLayout(horizontalSpacing: 10, verticalSpacing: 2) {
            footerText(
                String.localizedStringWithFormat(
                    NSLocalizedString("poll_responses_%lld", bundle: .module, comment: ""), poll.totalVotes)
            )
            .monospacedDigit()
            .accessibilityIdentifier("poll-total-\(commentId)")

            footerText(privacyText(for: poll))

            if let closesAt = poll.closesAt {
                footerText(
                    closed
                        ? NSLocalizedString("poll_closed", bundle: .module, comment: "")
                        : String(
                            format: NSLocalizedString("poll_closes_at_%@", bundle: .module, comment: ""),
                            closesAt.formatted(date: .abbreviated, time: .omitted))
                )
                .accessibilityIdentifier("poll-closes-\(commentId)")
            }
        }
    }

    @ViewBuilder
    private func actionFooter(for poll: CommentPoll, results: Bool, closed: Bool) -> some View {
        let voted = PollRules.hasVoted(comment.comment)
        let locked = PollRules.resultsLocked(comment.comment)
        let changeVote = voted && results && !closed
        // The web shows this toggle on locked polls too, where it can't reveal anything; it is left out here.
        let toggleResults = !voted && !closed && !locked
        let voters = PollRules.canSeeVoters(poll, isSiteAdmin: sdk.isSiteAdmin) && poll.totalVotes > 0

        if voted || changeVote || toggleResults || voters {
            PollFlowLayout(horizontalSpacing: 12, verticalSpacing: 4) {
                if voted {
                    votedPill
                }
                if changeVote {
                    PollLinkButton(
                        title: NSLocalizedString("poll_change_vote", bundle: .module, comment: ""),
                        identifier: "poll-change-vote-\(commentId)"
                    ) {
                        comment.pollShowResults = false
                    }
                }
                if toggleResults {
                    PollLinkButton(
                        title: NSLocalizedString(
                            results ? "poll_hide_results" : "poll_show_results", bundle: .module, comment: ""),
                        identifier: "poll-toggle-results-\(commentId)"
                    ) {
                        comment.pollShowResults = !results
                    }
                }
                if voters {
                    PollLinkButton(
                        title: NSLocalizedString("poll_voters_show", bundle: .module, comment: ""),
                        identifier: "poll-voters-\(commentId)"
                    ) {
                        showVoters = true
                    }
                }
            }
        }
    }

    private var votedPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark")
                .font(.caption2.weight(.bold))
                .accessibilityHidden(true)
            Text(NSLocalizedString("poll_vote_saved", bundle: .module, comment: ""))
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(theme.resolvePollAccentColor())
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.resolvePollOptionBackgroundColor()))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("poll-saved-\(commentId)")
    }

    private func footerText(_ text: String) -> Text {
        Text(text)
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private func privacyText(for poll: CommentPoll) -> String {
        switch poll.privacy {
        case ._2: return NSLocalizedString("poll_votes_public_visible", bundle: .module, comment: "")
        case ._1: return NSLocalizedString("poll_votes_admins_visible", bundle: .module, comment: "")
        default: return NSLocalizedString("poll_votes_anonymous", bundle: .module, comment: "")
        }
    }
}

// MARK: - Option

private struct PollOptionRow: View {
    let label: String
    let percent: Int
    let isSelected: Bool
    let showsResults: Bool
    let isClosed: Bool
    let action: () -> Void

    @Environment(\.fastCommentsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var markSize = PollStyle.markSize

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                mark

                Text(label)
                    .font(theme.resolveBodyFont().weight(.medium))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(verbatim: "\(percent)%")
                    .font(theme.resolveBodyFont().monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .frame(minWidth: 36, alignment: .trailing)
                    .opacity(showsResults ? 1 : 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(alignment: .leading) { resultBar }
            .contentShape(PollStyle.shape(radius: PollStyle.optionRadius))
        }
        .buttonStyle(PollOptionButtonStyle(isSelected: isSelected, isEnabled: !isClosed))
        .disabled(isClosed)
        // Bars slide when a live vote moves them, like the web's width transition.
        .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: barFraction)
        .animation(.easeOut(duration: 0.18), value: isSelected)
        .accessibilityLabel(label)
        .accessibilityValue(showsResults ? "\(percent)%" : "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var barFraction: CGFloat {
        showsResults ? CGFloat(percent) / 100 : 0
    }

    private var resultBar: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(isSelected ? theme.resolvePollSelectedBarColor() : theme.resolvePollBarColor())
                .frame(width: geometry.size.width * barFraction)
        }
    }

    private var mark: some View {
        ZStack {
            PollStyle.shape(radius: PollStyle.markRadius)
                .fill(isSelected ? theme.resolvePollAccentColor() : Color.clear)
            PollStyle.shape(radius: PollStyle.markRadius)
                .strokeBorder(
                    isSelected ? theme.resolvePollAccentColor() : theme.resolvePollBorderColor(), lineWidth: 1)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(theme.resolvePollAccentTextColor())
            }
        }
        .frame(width: markSize, height: markSize)
    }
}

private struct PollOptionButtonStyle: ButtonStyle {
    let isSelected: Bool
    let isEnabled: Bool

    @Environment(\.fastCommentsTheme) private var theme

    func makeBody(configuration: Configuration) -> some View {
        let shape = PollStyle.shape(radius: PollStyle.optionRadius)
        configuration.label
            .background(
                configuration.isPressed && isEnabled
                    ? theme.resolvePollOptionPressedBackgroundColor()
                    : theme.resolvePollOptionBackgroundColor()
            )
            .clipShape(shape)
            .overlay(shape.strokeBorder(isSelected ? theme.resolvePollAccentColor() : Color.clear, lineWidth: 1))
    }
}

// MARK: - Footer link

/// A poll footer action, drawn as the web's underlined text button. The tap area reaches 44 points without spacing the
/// footer out to match: the outer negative padding takes back what the inner padding adds to the layout.
struct PollLinkButton: View {
    let title: String
    let identifier: String
    var color: Color?
    let action: () -> Void

    @Environment(\.fastCommentsTheme) private var theme

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .underline()
                .foregroundStyle(color ?? theme.resolvePollAccentColor())
                .padding(.vertical, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -8)
        .accessibilityIdentifier(identifier)
    }
}
