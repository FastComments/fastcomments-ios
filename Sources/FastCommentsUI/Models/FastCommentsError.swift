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

    /// Decode a thrown `ErrorResponse` (the 3.0.0 non-2xx `APIError` body) into a `FastCommentsError`.
    /// Returns nil for transport-level errors with no decodable API error body.
    public init?(decoding error: Error) {
        guard case let ErrorResponse.error(_, data, _, _) = error,
            let data,
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        let translated = (json["translatedError"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let reasonValue = (json["reason"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        guard translated != nil || reasonValue != nil else { return nil }
        self.code = json["code"] as? String
        self.reason = reasonValue
        self.translatedError = translated
    }

    /// A user-facing message for any thrown error: the API's localized `translatedError`/`reason`
    /// when the thrown `ErrorResponse` body can be decoded, otherwise the system description.
    public static func userMessage(from error: Error) -> String {
        if let apiError = FastCommentsError(decoding: error), let message = apiError.errorDescription {
            return message
        }
        return error.localizedDescription
    }
}
