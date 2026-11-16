import Foundation
import FastCommentsSwift

/// Poll rules shared by the poll card, the composer and the SDK. Mirrors the web widget's polls extension.
enum PollRules {

    static func isClosed(_ poll: CommentPoll, now: Date = Date()) -> Bool {
        guard let closesAt = poll.closesAt else { return false }
        return closesAt <= now
    }

    static func percent(votes: Int, total: Int) -> Int {
        guard total > 0 else { return 0 }
        return Int((Double(votes) * 100 / Double(total)).rounded())
    }

    static func hasVoted(_ comment: PublicComment) -> Bool {
        !(comment.myPollVotes ?? []).isEmpty
    }

    static func isSelected(_ comment: PublicComment, optionId: String) -> Bool {
        comment.myPollVotes?.contains(optionId) == true
    }

    /// The author can withhold tallies until you answer. The server already zeroes the counts in that case, so
    /// this only decides what the card renders.
    static func resultsLocked(_ comment: PublicComment, now: Date = Date()) -> Bool {
        guard let poll = comment.poll else { return false }
        return poll.requireVoteToSeeResults == true && !hasVoted(comment) && !isClosed(poll, now: now)
    }

    /// `showResultsOverride` is what the viewer last chose with "Show results" or "Change vote". A closed poll has
    /// nothing left to vote on, so it always shows its results and the viewer's choice no longer applies.
    static func isShowingResults(_ comment: PublicComment, showResultsOverride: Bool?, now: Date = Date()) -> Bool {
        guard let poll = comment.poll else { return false }
        if isClosed(poll, now: now) { return true }
        if resultsLocked(comment, now: now) { return false }
        return showResultsOverride ?? hasVoted(comment)
    }

    /// An anonymous session still has a user object, so holding one is not the same as being logged in.
    static func canVote(
        config: CustomConfigParameters?, currentUser: UserSessionInfo?, poll: CommentPoll, now: Date = Date()
    ) -> Bool {
        if isClosed(poll, now: now) { return false }
        if config?.pollVoting == ._1 { return true }
        return currentUser != nil && currentUser?.isAnonSession != true
    }

    /// The server only names voters of an admins-only poll to admins and moderators, so nobody else is offered a list
    /// that can only fail.
    static func canSeeVoters(_ poll: CommentPoll, isSiteAdmin: Bool) -> Bool {
        switch poll.privacy {
        case ._2: return true
        case ._1: return isSiteAdmin
        default: return false
        }
    }

    /// Live chat keeps polls out of its composer, like the web live chat and its single-line input.
    static func canCreatePoll(config: CustomConfigParameters?, isSiteAdmin: Bool, isLiveChat: Bool) -> Bool {
        if isLiveChat || config?.useSingleLineCommentInput == true { return false }
        switch config?.pollCreation {
        case ._2: return true
        case ._1: return isSiteAdmin
        default: return false
        }
    }

    /// Questions and option labels are stored entity-escaped. This is one pass, so "&amp;lt;" correctly stays "&lt;".
    static func plainText(fromEscaped text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var remainder = Substring(text)
        while let ampersand = remainder.firstIndex(of: "&") {
            result += remainder[..<ampersand]
            let afterAmpersand = remainder[ampersand...].dropFirst()
            if let semicolon = afterAmpersand.prefix(10).firstIndex(of: ";"),
                let decoded = decodeEntity(afterAmpersand[..<semicolon])
            {
                result.append(decoded)
                remainder = afterAmpersand[semicolon...].dropFirst()
            } else {
                result.append("&")
                remainder = afterAmpersand
            }
        }
        result += remainder
        return result
    }

    private static func decodeEntity(_ entity: Substring) -> Character? {
        switch entity {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return " "
        default: break
        }
        guard entity.first == "#" else { return nil }
        let digits = entity.dropFirst()
        let scalarValue: UInt32?
        if digits.first == "x" || digits.first == "X" {
            scalarValue = UInt32(digits.dropFirst(), radix: 16)
        } else {
            scalarValue = UInt32(digits)
        }
        return scalarValue.flatMap(Unicode.Scalar.init).map(Character.init)
    }
}
