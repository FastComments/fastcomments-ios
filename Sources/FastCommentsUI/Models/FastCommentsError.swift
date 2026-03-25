import Foundation
import FastCommentsSwift

/// SDK-level error wrapping API errors from the generated client.
public struct FastCommentsError: LocalizedError, Sendable {
    public let code: String?
    public let reason: String?
    public let translatedError: String?

    public var errorDescription: String? {
        translatedError ?? reason ?? "An unknown error occurred"
    }

    public init(code: String? = nil, reason: String? = nil, translatedError: String? = nil) {
        self.code = code
        self.reason = reason
        self.translatedError = translatedError
    }

    public init(from response: CreateCommentPublic200Response) {
        self.code = response.code
        self.reason = response.reason
        self.translatedError = response.translatedError
    }

    public init(from response: VoteComment200Response) {
        self.code = response.code
        self.reason = response.reason
        self.translatedError = response.translatedError
    }

    public init(from response: GetFeedPostsPublic200Response) {
        self.code = response.code
        self.reason = response.reason
        self.translatedError = response.translatedError
    }
}
