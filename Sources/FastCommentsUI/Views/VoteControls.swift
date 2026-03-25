import SwiftUI
import FastCommentsSwift

/// Vote controls supporting both UpDown and Heart styles.
public struct VoteControls: View {
    @ObservedObject var comment: RenderableComment
    let voteStyle: VoteStyle
    var onUpVote: (() -> Void)?
    var onDownVote: (() -> Void)?
    var onRemoveVote: (() -> Void)?

    @Environment(\.fastCommentsTheme) private var theme

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
        HStack(spacing: 4) {
            Button {
                if comment.comment.isVotedUp == true {
                    onRemoveVote?()
                } else {
                    onUpVote?()
                }
            } label: {
                Image(systemName: comment.comment.isVotedUp == true ? "arrow.up.circle.fill" : "arrow.up.circle")
                    .foregroundStyle(comment.comment.isVotedUp == true ? theme.resolveActionButtonColor() : .secondary)
            }
            .buttonStyle(.plain)

            Text(voteCountText)
                .font(.caption)
                .foregroundStyle(voteCount == 0 ? theme.resolveVoteCountZeroColor() : theme.resolveVoteCountColor())
                .monospacedDigit()

            Button {
                if comment.comment.isVotedDown == true {
                    onRemoveVote?()
                } else {
                    onDownVote?()
                }
            } label: {
                Image(systemName: comment.comment.isVotedDown == true ? "arrow.down.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(comment.comment.isVotedDown == true ? .red : .secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // VoteStyle._1 = Heart
    private var heartControls: some View {
        Button {
            if comment.comment.isVotedUp == true {
                onRemoveVote?()
            } else {
                onUpVote?()
            }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: comment.comment.isVotedUp == true ? "heart.fill" : "heart")
                    .foregroundStyle(comment.comment.isVotedUp == true ? .red : .secondary)
                if voteCount > 0 {
                    Text("\(voteCount)")
                        .font(.caption)
                        .foregroundStyle(theme.resolveVoteCountColor())
                        .monospacedDigit()
                }
            }
        }
        .buttonStyle(.plain)
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
