import Foundation
import Combine
import FastCommentsSwift

/// Configuration for the FastComments widget. Wraps the parameters needed
/// to identify a tenant, page, and optional SSO session.
public struct FastCommentsWidgetConfig: Sendable {
    public var tenantId: String
    public var urlId: String
    public var url: String
    public var pageTitle: String?
    public var region: String?
    public var sso: String?
    public var locale: String?

    public init(tenantId: String, urlId: String, url: String = "", pageTitle: String? = nil,
                region: String? = nil, sso: String? = nil, locale: String? = nil) {
        self.tenantId = tenantId
        self.urlId = urlId
        self.url = url
        self.pageTitle = pageTitle
        self.region = region
        self.sso = sso
        self.locale = locale
    }
}

/// Main SDK for the FastComments threaded comment system.
/// Manages API interactions, state, live events, and authentication.
/// Mirrors FastCommentsSDK.java from Android.
@MainActor
public final class FastCommentsSDK: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var commentCountOnServer: Int = 0
    @Published public private(set) var newRootCommentCount: Int = 0
    @Published public private(set) var currentUser: UserSessionInfo?
    @Published public private(set) var isSiteAdmin: Bool = false
    @Published public private(set) var isClosed: Bool = false
    @Published public private(set) var hasBillingIssue: Bool = false
    @Published public var commentsVisible: Bool = true
    @Published public private(set) var isDemo: Bool = false
    @Published public private(set) var hasMore: Bool = false
    @Published public private(set) var blockingErrorMessage: String?
    @Published public private(set) var warningMessage: String?
    @Published public private(set) var isLoading: Bool = false

    // MARK: - Public Properties

    public let config: FastCommentsWidgetConfig
    public let commentsTree = CommentsTree()
    public var theme: FastCommentsTheme?
    public private(set) var currentPage: Int = 0
    public private(set) var currentSkip: Int = 0
    public var pageSize: Int = 30
    public var showLiveRightAway: Bool = true
    public var defaultSortDirection: SortDirections = .nf

    public var disableUnverifiedLabel: Bool {
        customConfig?.disableUnverifiedLabel ?? false
    }

    public var disableToolbar: Bool {
        customConfig?.disableToolbar ?? false
    }

    // MARK: - Internal

    var broadcastIdsSent: Set<String> = []
    private var commentsTreeSubscription: AnyCancellable?
    private let apiConfig: FastCommentsSwiftAPIConfiguration
    private let liveEventSubscriber = LiveEventSubscriber()
    private var liveEventSubscription: SubscribeToChangesResult?
    private var tenantIdWS: String?
    private var urlIdWS: String?
    private var userIdWS: String?
    private var editKey: String?
    private var sessionId: String?
    private var customConfig: CustomConfigParameters?

    /// Server-provided presence poll state: 0 = disabled, 1 = poll
    private var presencePollState: Int = 0
    private var presencePollTask: Task<Void, Never>?

    // MARK: - Init

    public init(config: FastCommentsWidgetConfig) {
        self.config = config
        self.apiConfig = FastCommentsSwiftAPIConfiguration(
            basePath: Self.getAPIBasePath(config: config)
        )

        // Forward commentsTree changes to SDK so SwiftUI re-renders
        commentsTreeSubscription = commentsTree.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }

        // Wire presence requests from the tree back to the SDK
        commentsTree.onPresenceNeeded = { [weak self] userIds in
            Task { [weak self] in
                await self?.fetchPresenceForUsers(userIds)
            }
        }
    }

    // MARK: - Static Helpers

    public static func getAPIBasePath(config: FastCommentsWidgetConfig) -> String {
        if config.region == "eu" {
            return "https://eu.fastcomments.com"
        }
        return "https://fastcomments.com"
    }

    // MARK: - Load & Paginate

    /// Initial load of comments. Sets up live events after first successful fetch.
    @discardableResult
    public func load() async throws -> GetCommentsPublic200Response {
        isLoading = true
        defer { isLoading = false }

        let response = try await PublicAPI.getCommentsPublic(
            tenantId: config.tenantId,
            urlId: config.urlId,
            page: 0,
            direction: defaultSortDirection,
            sso: config.sso,
            skip: 0,
            limit: pageSize,
            countChildren: true,
            includeConfig: true,
            countAll: true,
            locale: config.locale,
            includeNotificationCount: true,
            asTree: true,
            maxTreeDepth: 2,
            apiConfiguration: apiConfig
        )

        processCommentsResponse(response, isInitialLoad: true)
        return response
    }

    /// Load next page of comments.
    @discardableResult
    public func loadMore() async throws -> GetCommentsPublic200Response {
        let previousSkip = currentSkip
        let previousPage = currentPage
        currentSkip += pageSize
        currentPage += 1

        do {
            let response = try await PublicAPI.getCommentsPublic(
                tenantId: config.tenantId,
                urlId: config.urlId,
                page: currentPage,
                direction: defaultSortDirection,
                sso: config.sso,
                skip: currentSkip,
                limit: pageSize,
                countChildren: true,
                countAll: true,
                asTree: true,
                maxTreeDepth: 2,
                apiConfiguration: apiConfig
            )

            if !(response.comments ?? []).isEmpty {
                commentsTree.appendComments((response.comments ?? []))
            }
            hasMore = response.hasMore ?? false
            return response
        } catch {
            currentSkip = previousSkip
            currentPage = previousPage
            throw error
        }
    }

    /// Load all remaining comments.
    @discardableResult
    public func loadAll() async throws -> GetCommentsPublic200Response {
        let response = try await PublicAPI.getCommentsPublic(
            tenantId: config.tenantId,
            urlId: config.urlId,
            page: 0,
            direction: defaultSortDirection,
            sso: config.sso,
            skip: 0,
            limit: 999999,
            countChildren: true,
            countAll: true,
            asTree: true,
            maxTreeDepth: 999,
            apiConfiguration: apiConfig
        )

        commentsTree.build(comments: (response.comments ?? []))
        commentCountOnServer = response.commentCount ?? 0
        hasMore = false
        return response
    }

    /// Fetch child comments for a specific parent (reply pagination).
    public func getCommentsForParent(parentId: String, skip: Int, limit: Int) async throws -> [PublicComment] {
        let response = try await PublicAPI.getCommentsPublic(
            tenantId: config.tenantId,
            urlId: config.urlId,
            sso: config.sso,
            skip: skip,
            limit: limit,
            countChildren: true,
            asTree: true,
            maxTreeDepth: 1,
            parentId: parentId,
            apiConfiguration: apiConfig
        )

        return (response.comments ?? [])
    }

    // MARK: - Comment CRUD

    /// Post a new comment or reply.
    @discardableResult
    public func postComment(text: String, parentId: String? = nil, mentions: [CommentUserMentionInfo]? = nil) async throws -> PublicComment {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw FastCommentsError(reason: "Comment text cannot be empty")
        }

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let commentData = CommentData(
            date: Int64(Date().timeIntervalSince1970 * 1000),
            commenterName: currentUser?.username ?? currentUser?.displayName ?? "",
            commenterEmail: currentUser?.email,
            comment: trimmed,
            userId: currentUser?.id,
            avatarSrc: currentUser?.avatarSrc,
            parentId: parentId,
            mentions: mentions,
            pageTitle: config.pageTitle,
            url: config.url.isEmpty ? config.urlId : config.url,
            urlId: config.urlId
        )

        let response = try await PublicAPI.createCommentPublic(
            tenantId: config.tenantId,
            urlId: config.urlId,
            broadcastId: broadcastId,
            commentData: commentData,
            sessionId: sessionId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        // Update user session if returned
        if let user = response.user {
            currentUser = user
        }
        if let newUserIdWS = response.userIdWS, newUserIdWS != userIdWS {
            userIdWS = newUserIdWS
            subscribeToLiveEvents()
        }

        // Add to tree
        if let comment = response.comment {
            commentsTree.addComment(comment, displayNow: true, sortDirection: defaultSortDirection)
            commentCountOnServer += 1
            return comment
        }
        throw FastCommentsError(reason: "No comment returned from API")
    }

    /// Edit an existing comment's text.
    public func editComment(commentId: String, newText: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let request = CommentTextUpdateRequest(comment: newText)
        _ = try await PublicAPI.setCommentText(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            commentTextUpdateRequest: request,
            editKey: editKey,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
    }

    /// Delete a comment.
    public func deleteComment(commentId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        _ = try await PublicAPI.deleteCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            editKey: editKey,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        commentsTree.removeComment(commentId: commentId)
        commentCountOnServer -= 1
    }

    // MARK: - Voting

    /// Vote on a comment (upvote or downvote).
    @discardableResult
    public func voteComment(commentId: String, isUpvote: Bool,
                            commenterName: String? = nil, commenterEmail: String? = nil) async throws -> VoteComment200Response {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let params = VoteBodyParams(
            commenterEmail: commenterEmail ?? currentUser?.email,
            commenterName: commenterName ?? currentUser?.username ?? currentUser?.displayName,
            voteDir: isUpvote ? .up : .down,
            url: config.url
        )

        let response = try await PublicAPI.voteComment(
            tenantId: config.tenantId,
            commentId: commentId,
            urlId: config.urlId,
            broadcastId: broadcastId,
            voteBodyParams: params,
            sessionId: sessionId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        // Update local comment state
        if let comment = commentsTree.commentsById[commentId] {
            if isUpvote {
                // If was downvoted, undo that first
                if comment.comment.isVotedDown == true {
                    comment.comment.votesDown = max(0, (comment.comment.votesDown ?? 0) - 1)
                }
                comment.comment.votesUp = (comment.comment.votesUp ?? 0) + 1
                comment.comment.isVotedUp = true
                comment.comment.isVotedDown = false
            } else {
                // If was upvoted, undo that first
                if comment.comment.isVotedUp == true {
                    comment.comment.votesUp = max(0, (comment.comment.votesUp ?? 0) - 1)
                }
                comment.comment.votesDown = (comment.comment.votesDown ?? 0) + 1
                comment.comment.isVotedDown = true
                comment.comment.isVotedUp = false
            }
            comment.comment.votes = (comment.comment.votesUp ?? 0) - (comment.comment.votesDown ?? 0)
            comment.comment.myVoteId = response.voteId
            comment.objectWillChange.send()
        }

        return response
    }

    /// Remove a vote from a comment.
    public func deleteCommentVote(commentId: String, voteId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        _ = try await PublicAPI.deleteCommentVote(
            tenantId: config.tenantId,
            commentId: commentId,
            voteId: voteId,
            urlId: config.urlId,
            broadcastId: broadcastId,
            editKey: editKey,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        // Update local comment state — undo the vote
        if let comment = commentsTree.commentsById[commentId] {
            if comment.comment.isVotedUp == true {
                comment.comment.votesUp = max(0, (comment.comment.votesUp ?? 0) - 1)
            } else if comment.comment.isVotedDown == true {
                comment.comment.votesDown = max(0, (comment.comment.votesDown ?? 0) - 1)
            }
            comment.comment.votes = (comment.comment.votesUp ?? 0) - (comment.comment.votesDown ?? 0)
            comment.comment.isVotedUp = false
            comment.comment.isVotedDown = false
            comment.comment.myVoteId = nil
            comment.objectWillChange.send()
        }
    }

    // MARK: - Moderation

    public func flagComment(commentId: String) async throws {
        _ = try await PublicAPI.flagCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            isFlagged: true,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
    }

    public func blockUser(commentId: String) async throws {
        let params = PublicBlockFromCommentParams(commentIds: nil)
        _ = try await PublicAPI.blockFromCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            publicBlockFromCommentParams: params,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
    }

    public func pinComment(commentId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        _ = try await PublicAPI.pinComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
    }

    public func lockComment(commentId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        _ = try await PublicAPI.lockComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
    }

    // MARK: - Image Upload

    /// Upload an image and return its URL.
    public func uploadImage(imageData: Data, filename: String) async throws -> String {
        let boundary = UUID().uuidString
        let basePath = apiConfig.basePath
        var urlString = "\(basePath)/upload-image/\(config.tenantId)?urlId=\(config.urlId)&sizePreset=CrossPlatform"
        if let sso = config.sso {
            urlString += "&sso=\(sso.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? sso)"
        }
        guard let url = URL(string: urlString) else {
            throw FastCommentsError(reason: "Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw FastCommentsError(reason: "Image upload failed")
        }

        let uploadResponse = try CodableHelper().jsonDecoder.decode(UploadImageResponse.self, from: data)
        if let imageUrl = uploadResponse.url {
            return imageUrl
        }
        // Pick a mid-size asset (~768-1024w) from the media array
        if let media = uploadResponse.media, !media.isEmpty {
            let preferred = media.first(where: { $0.w >= 768 && $0.w <= 1024 }) ?? media.first!
            return preferred.src
        }
        throw FastCommentsError(reason: "No image URL returned from upload")
    }

    // MARK: - User Search (for mentions)

    public func searchUsers(query: String) async throws -> [UserSearchResult] {
        let response = try await PublicAPI.searchUsers(
            tenantId: config.tenantId,
            urlId: config.urlId,
            usernameStartsWith: query,
            sso: config.sso,
            apiConfiguration: apiConfig
        )
        return response.users ?? []
    }

    // MARK: - Helpers

    public func shouldShowLoadAll() -> Bool {
        hasMore && commentCountOnServer > 0
    }

    public func getCountRemainingToShow() -> Int {
        max(0, commentCountOnServer - commentsTree.totalSize())
    }

    /// Clean up WebSocket connections and timers.
    public func cleanup() {
        liveEventSubscription?.close()
        liveEventSubscription = nil
        presencePollTask?.cancel()
        presencePollTask = nil
    }

    // MARK: - Live Events (Internal)

    func subscribeToLiveEvents() {
        liveEventSubscription?.close()

        guard let tenantIdWS = tenantIdWS,
              let urlIdWS = urlIdWS else { return }

        let liveConfig = LiveEventConfig(
            tenantId: config.tenantId,
            urlId: config.urlId,
            urlIdWS: urlIdWS,
            userIdWS: userIdWS ?? "",
            region: config.region
        )

        liveEventSubscriber.setOnConnectionStatusChange { [weak self] isConnected, lastEventTime in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isConnected {
                    let isReconnect = lastEventTime != nil && lastEventTime! > 0
                    if isReconnect {
                        self.commentsTree.clearAllPresence()
                    }
                    await self.fetchUserPresenceStatuses()
                    self.startPresencePollingIfNeeded()
                }
            }
        }

        liveEventSubscription = liveEventSubscriber.subscribeToChanges(
            config: liveConfig,
            handleLiveEvent: { [weak self] event in
                Task { @MainActor [weak self] in
                    self?.handleLiveEvent(event)
                }
            }
        )
    }

    func handleLiveEvent(_ event: LiveEvent) {
        // Skip events we broadcasted
        if let broadcastId = event.broadcastId, broadcastIdsSent.remove(broadcastId) != nil {
            return
        }

        switch event.type {
        case .newComment:
            if let comment = event.comment {
                let publicComment = LiveEventHandler.toPublicComment(comment)
                commentsTree.addComment(publicComment, displayNow: showLiveRightAway, sortDirection: defaultSortDirection)
                commentCountOnServer += 1
            }
        case .updatedComment:
            if let comment = event.comment {
                let publicComment = LiveEventHandler.toPublicComment(comment)
                commentsTree.updateComment(publicComment)
            }
        case .deletedComment:
            if let comment = event.comment {
                commentsTree.removeComment(commentId: comment.id ?? "")
                commentCountOnServer -= 1
            }
        case .newVote:
            if let vote = event.vote, let commentId = vote.commentId, let comment = commentsTree.commentsById[commentId] {
                let direction = vote.direction ?? 1
                if direction > 0 {
                    comment.comment.votesUp = (comment.comment.votesUp ?? 0) + 1
                } else {
                    comment.comment.votesDown = (comment.comment.votesDown ?? 0) + 1
                }
                comment.comment.votes = (comment.comment.votesUp ?? 0) - (comment.comment.votesDown ?? 0)
                comment.objectWillChange.send()
            }
        case .deletedVote:
            if let vote = event.vote, let commentId = vote.commentId, let comment = commentsTree.commentsById[commentId] {
                let direction = vote.direction ?? 1
                if direction > 0 {
                    comment.comment.votesUp = max(0, (comment.comment.votesUp ?? 0) - 1)
                } else {
                    comment.comment.votesDown = max(0, (comment.comment.votesDown ?? 0) - 1)
                }
                comment.comment.votes = (comment.comment.votesUp ?? 0) - (comment.comment.votesDown ?? 0)
                comment.objectWillChange.send()
            }
        case .presenceUpdate:
            // Presence update: uj = user joins, ul = user leaves
            if let joins = event.uj {
                for userId in joins {
                    commentsTree.updateUserPresence(userId: userId, isOnline: true)
                }
            }
            if let leaves = event.ul {
                for userId in leaves {
                    commentsTree.updateUserPresence(userId: userId, isOnline: false)
                }
            }
        case .threadStateChange:
            if let closed = event.isClosed {
                isClosed = closed
            }
        case .updateBadges:
            // Badge updates for comments
            break
        case .newConfig:
            // Server pushed config change
            break
        default:
            break
        }
    }

    // MARK: - Presence

    func fetchUserPresenceStatuses() async {
        guard let urlIdWS = urlIdWS, let tenantIdWS = tenantIdWS else { return }

        var userIds = Set<String>()
        for node in commentsTree.visibleNodes {
            if let comment = node as? RenderableComment {
                if let userId = comment.comment.userId { userIds.insert(userId) }
                if let anonUserId = comment.comment.anonUserId { userIds.insert(anonUserId) }
            }
        }

        guard !userIds.isEmpty else { return }
        await fetchPresenceForUsers(Array(userIds))
    }

    private func fetchPresenceForUsers(_ userIds: [String]) async {
        guard let urlIdWS = urlIdWS, let tenantIdWS = tenantIdWS else { return }
        let csv = userIds.joined(separator: ",")

        do {
            let response = try await PublicAPI.getUserPresenceStatuses(
                tenantId: tenantIdWS,
                urlIdWS: urlIdWS,
                userIds: csv,
                apiConfiguration: apiConfig
            )

            for (userId, isOnline) in (response.userIdsOnline ?? [:]) {
                commentsTree.updateUserPresence(userId: userId, isOnline: isOnline)
            }
        } catch {
            // Presence is non-critical; log and continue
        }
    }

    /// Start periodic presence polling only if the server indicated poll mode.
    private func startPresencePollingIfNeeded() {
        presencePollTask?.cancel()
        presencePollTask = nil

        guard presencePollState == 1 else { return }

        let interval: TimeInterval = 30.0 + Double.random(in: 0..<10)
        presencePollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                await self.fetchUserPresenceStatuses()
            }
        }
    }

    // MARK: - Private Helpers

    private func processCommentsResponse(_ response: GetCommentsPublic200Response, isInitialLoad: Bool) {
        commentsTree.build(comments: (response.comments ?? []))

        commentCountOnServer = response.commentCount ?? 0
        currentUser = response.user
        isSiteAdmin = response.isSiteAdmin ?? false
        hasBillingIssue = response.hasBillingIssue ?? false
        isDemo = response.isDemo ?? false
        hasMore = response.hasMore ?? false
        isClosed = response.isClosed ?? false
        customConfig = response.customConfig
        currentPage = (response.pageNumber ?? 0)
        currentSkip = 0
        presencePollState = response.presencePollState ?? 0

        // Extract WebSocket parameters
        let newTenantIdWS = response.tenantIdWS
        let newUrlIdWS = response.urlIdWS
        let newUserIdWS = response.userIdWS

        if newTenantIdWS != nil { tenantIdWS = newTenantIdWS }
        if newUrlIdWS != nil { urlIdWS = newUrlIdWS }

        let wsNeedsReconnect = isInitialLoad || newUserIdWS != userIdWS
        if newUserIdWS != nil { userIdWS = newUserIdWS }

        if wsNeedsReconnect {
            subscribeToLiveEvents()
        }

        // Check for blocking errors (translatedError blocks, translatedWarning does not)
        if let translatedError = response.translatedError, !translatedError.isEmpty {
            blockingErrorMessage = translatedError
        }
        if let translatedWarning = response.translatedWarning, !translatedWarning.isEmpty {
            warningMessage = translatedWarning
        }
    }
}
