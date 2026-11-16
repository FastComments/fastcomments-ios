import Foundation
import FastCommentsSwift

/// A poll being written in the comment composer. Limits match the server's validation.
public struct PollDraft: Equatable, Sendable {
    public static let minOptions = 2
    public static let maxOptions = 10
    public static let maxQuestionLength = 200
    public static let maxOptionLength = 100
    /// The durations offered by the poll builder, in days. 0 means the poll never closes.
    public static let closesDaysChoices = [0, 1, 3, 7]

    /// One answer. The id keeps a text field's focus and contents attached to its row when another row is removed.
    public struct Option: Identifiable, Equatable, Sendable {
        public let id: UUID
        public var text: String

        public init(text: String = "") {
            self.id = UUID()
            self.text = text
        }
    }

    public enum ValidationError: Equatable, Sendable {
        case questionRequired
        case tooFewOptions

        /// The message the poll builder shows for this error.
        public var message: String {
            switch self {
            case .questionRequired:
                return NSLocalizedString("poll_error_question_required", bundle: .module, comment: "")
            case .tooFewOptions:
                return NSLocalizedString("poll_error_min_options", bundle: .module, comment: "")
            }
        }
    }

    public var question: String
    public var options: [Option]
    public var closesDays: Int
    public var privacy: PollPrivacy
    public var requireVoteToSeeResults: Bool

    public init(
        question: String = "",
        options: [String] = ["", ""],
        closesDays: Int = 0,
        privacy: PollPrivacy = ._0,
        requireVoteToSeeResults: Bool = false
    ) {
        self.question = question
        self.options = options.map { Option(text: $0) }
        self.closesDays = closesDays
        self.privacy = privacy
        self.requireVoteToSeeResults = requireVoteToSeeResults
    }

    public var canAddOption: Bool { options.count < Self.maxOptions }
    public var canRemoveOption: Bool { options.count > Self.minOptions }

    /// Returns nil when the draft can be posted.
    public func validate() -> ValidationError? {
        if question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .questionRequired
        }
        if filledOptions.count < Self.minOptions {
            return .tooFewOptions
        }
        return nil
    }

    /// The API input for this draft. Options left blank are dropped.
    public func toInput(now: Date = Date()) -> CommentPollInput {
        CommentPollInput(
            question: question.trimmingCharacters(in: .whitespacesAndNewlines),
            options: filledOptions,
            closesAt: closesDays > 0
                ? ISO8601DateFormatter().string(from: now.addingTimeInterval(TimeInterval(closesDays) * 86_400))
                : nil,
            privacy: privacy == ._0 ? nil : privacy.rawValue,
            requireVoteToSeeResults: requireVoteToSeeResults ? true : nil
        )
    }

    /// Flattens pasted text to one line, then trims to `maxLength`. The server counts UTF-16 units, and this drops whole
    /// characters until the text fits so an emoji is never cut in half.
    static func sanitize(_ text: String, maxLength: Int) -> String {
        var result = text
        if result.contains(where: { $0.isWhitespace && $0 != " " }) {
            result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        }
        while result.utf16.count > maxLength {
            result.removeLast()
        }
        return result
    }

    private var filledOptions: [String] {
        options.compactMap {
            let trimmed = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
}
