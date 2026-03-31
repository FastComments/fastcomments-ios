import SwiftUI
import FastCommentsSwift

/// Vote controls supporting both UpDown and Heart styles with smooth animations.
public struct VoteControls: View {
    @ObservedObject var comment: RenderableComment
    let voteStyle: VoteStyle
    var onUpVote: (() -> Void)?
    var onDownVote: (() -> Void)?
    var onRemoveVote: (() -> Void)?

    @Environment(\.fastCommentsTheme) private var theme
    @State private var voteAnimation: Bool = false

    public var body: some View {
        switch voteStyle {
        case ._0:
            upDownControls
        case ._1:
            heartControls
        }
    }

    // VoteStyle._0 = UpDown
    private var upDownControls: some View {
        HStack(spacing: 2) {
            Button {
                triggerAnimation()
                if comment.comment.isVotedUp == true {
                    onRemoveVote?()
                } else {
                    onUpVote?()
                }
            } label: {
                Image(systemName: comment.comment.isVotedUp == true ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(comment.comment.isVotedUp == true ? theme.resolveVoteActiveColor() : .secondary)
                    .scaleEffect(voteAnimation && comment.comment.isVotedUp == true ? 1.2 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vote-up-\(comment.comment.id)")

            Text(voteCountText)
                .font(.caption.weight(.medium))
                .foregroundStyle(voteCount == 0 ? theme.resolveVoteCountZeroColor() : theme.resolveVoteCountColor())
                .monospacedDigit()
                .animation(theme.animateVotes ? .spring(duration: 0.3) : nil, value: voteCount)
                .accessibilityIdentifier("vote-count-\(comment.comment.id)")

            Button {
                triggerAnimation()
                if comment.comment.isVotedDown == true {
                    onRemoveVote?()
                } else {
                    onDownVote?()
                }
            } label: {
                Image(systemName: comment.comment.isVotedDown == true ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(comment.comment.isVotedDown == true ? .red : .secondary)
                    .scaleEffect(voteAnimation && comment.comment.isVotedDown == true ? 1.2 : 1.0)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("vote-down-\(comment.comment.id)")
        }
    }

    // VoteStyle._1 = Heart
    private var heartControls: some View {
        Button {
            triggerAnimation()
            if comment.comment.isVotedUp == true {
                onRemoveVote?()
            } else {
                onUpVote?()
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: comment.comment.isVotedUp == true ? "heart.fill" : "heart")
                    .font(.system(size: 15))
                    .foregroundStyle(comment.comment.isVotedUp == true ? .red : .secondary)
                    .scaleEffect(voteAnimation ? 1.3 : 1.0)
                if voteCount > 0 {
                    Text("\(voteCount)")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(theme.resolveVoteCountColor())
                        .monospacedDigit()
                        .animation(theme.animateVotes ? .spring(duration: 0.3) : nil, value: voteCount)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("vote-up-\(comment.comment.id)")
    }

    // MARK: - Helpers

    private func triggerAnimation() {
        guard theme.animateVotes else { return }
        withAnimation(.spring(duration: 0.3, bounce: 0.5)) {
            voteAnimation = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            withAnimation(.spring(duration: 0.2)) {
                voteAnimation = false
            }
        }
    }

    private var voteCount: Int {
        comment.comment.votes ?? 0
    }

    private var voteCountText: String {
        let count = voteCount
        if count == 0 { return "0" }
        return count > 0 ? "+\(count)" : "\(count)"
    }
}
