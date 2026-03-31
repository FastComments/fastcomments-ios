import Foundation
import Combine
import FastCommentsSwift
import os.log

private let fcLog = Logger(subsystem: "com.fastcomments", category: "SDK")

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
    @Published public var toolbarEnabled: Bool = true
    @Published public var defaultFormattingButtonsEnabled: Bool = true
    @Published public var badgeAwardToShow: [CommentUserBadgeInfo]?

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

    /// Enable or disable the comment toolbar programmatically.
    public func setCommentToolbarEnabled(_ enabled: Bool) {
        toolbarEnabled = enabled
    }

    /// Enable or disable default formatting buttons (bold, italic, etc.) programmatically.
    public func setDefaultFormattingButtonsEnabled(_ enabled: Bool) {
        defaultFormattingButtonsEnabled = enabled
    }

    // MARK: - Global Toolbar Buttons

    @Published public private(set) var globalCustomToolbarButtons: [any CustomToolbarButton] = []

    /// Add a custom toolbar button that will appear on all comment input instances.
    public func addGlobalCustomToolbarButton(_ button: any CustomToolbarButton) {
        guard !globalCustomToolbarButtons.contains(where: { $0.id == button.id }) else { return }
        globalCustomToolbarButtons.append(button)
    }

    /// Remove a global custom toolbar button by ID.
    public func removeGlobalCustomToolbarButton(id: String) {
        globalCustomToolbarButtons.removeAll { $0.id == id }
    }

    /// Clear all global custom toolbar buttons.
    public func clearGlobalCustomToolbarButtons() {
        globalCustomToolbarButtons.removeAll()
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
            direction: defaultSortDirection,
            sso: config.sso,
            skip: 0,
            limit: pageSize + 1,
            limitChildren: pageSize,
            countChildren: true,
            includeConfig: true,
            countAll: true,
            locale: config.locale,
            includeNotificationCount: true,
            asTree: true,
            maxTreeDepth: 1,
            apiConfiguration: apiConfig
        )

        // Determine hasMore by checking if we got more root comments than pageSize
        var comments = response.comments ?? []
        let rootComments = comments.filter { $0.parentId == nil }
        let clientHasMore = rootComments.count > pageSize

        // Trim the extra probe comment if present
        if clientHasMore, let lastRoot = rootComments.last {
            comments.removeAll { $0.id == lastRoot.id }
            // Also remove its children
            func removeChildren(of parentId: String) {
                let children = comments.filter { $0.parentId == parentId }
                comments.removeAll { $0.parentId == parentId }
                for child in children { removeChildren(of: child.id) }
            }
            removeChildren(of: lastRoot.id)
        }

        // Build a modified response with trimmed comments
        var trimmedResponse = response
        trimmedResponse.comments = comments

        fcLog.info("load: returned \(response.comments?.count ?? 0) roots=\(rootComments.count) hasMore=\(clientHasMore, privacy: .public) commentCount=\(response.commentCount ?? -1)")

        processCommentsResponse(trimmedResponse, isInitialLoad: true, clientHasMore: clientHasMore)
        return response
    }

    /// Load next page of comments.
    @discardableResult
    public func loadMore() async throws -> GetCommentsPublic200Response {
        let previousSkip = currentSkip
        let previousPage = currentPage
        // With asTree, skip is based on root comment count, not pageSize
        let rootCount = commentsTree.visibleNodes.filter { ($0 as? RenderableComment)?.comment.parentId == nil }.count
        currentSkip = rootCount
        currentPage += 1

        do {
            let response = try await PublicAPI.getCommentsPublic(
                tenantId: config.tenantId,
                urlId: config.urlId,
                direction: defaultSortDirection,
                sso: config.sso,
                skip: currentSkip,
                limit: pageSize + 1,
                countChildren: true,
                asTree: true,
                maxTreeDepth: 0,
                apiConfiguration: apiConfig
            )

            var comments = response.comments ?? []
            let rootComments = comments.filter { $0.parentId == nil }
            let moreAvailable = rootComments.count > pageSize

            // Trim the extra probe comment
            if moreAvailable, let lastRoot = rootComments.last {
                comments.removeAll { $0.id == lastRoot.id }
            }

            fcLog.info("loadMore: skip=\(self.currentSkip) limit=\(self.pageSize) returned=\(rootComments.count) roots, trimmed to \(comments.count), hasMore=\(moreAvailable, privacy: .public)")

            if !comments.isEmpty {
                self.commentsTree.appendComments(comments)
            }
            if let serverCount = response.commentCount {
                commentCountOnServer = serverCount
            }
            hasMore = moreAvailable
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
            skipChildren: skip,
            limit: limit,
            limitChildren: limit,
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
        let response = try await PublicAPI.setCommentText(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            commentTextUpdateRequest: request,
            editKey: editKey,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        // Update local tree with server-rendered HTML
        if let result = response.comment,
           let existing = commentsTree.commentsById[commentId] {
            var updated = existing.comment
            updated.commentHTML = result.commentHTML
            updated.approved = result.approved
            commentsTree.updateComment(updated)
        }
    }

    /// Delete a comment.
    public func deleteComment(commentId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let response = try await PublicAPI.deleteCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            editKey: editKey,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

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

    /// Flag a comment.
    public func flagComment(commentId: String) async throws {
        let response = try await PublicAPI.flagCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            isFlagged: true,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        // Re-fetch after await — renderable may have been replaced by a live event
        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isFlagged = true
            renderable.objectWillChange.send()
        }
    }

    /// Unflag a previously flagged comment.
    public func unflagComment(commentId: String) async throws {
        let response = try await PublicAPI.flagCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            isFlagged: false,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isFlagged = false
            renderable.objectWillChange.send()
        }
    }

    /// Block the author of a comment. All comments by that user are marked as blocked.
    public func blockUser(commentId: String) async throws {
        // Pass all known comment IDs by this author so the response tells us which are blocked
        let authorCommentIds = getAuthorCommentIds(commentId: commentId)
        let params = PublicBlockFromCommentParams(commentIds: authorCommentIds.isEmpty ? nil : authorCommentIds)
        let response = try await PublicAPI.blockFromCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            publicBlockFromCommentParams: params,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        setBlockedStateForAuthor(commentId: commentId, blocked: true)
    }

    /// Unblock the author of a comment. Restores all their comments to normal.
    public func unblockUser(commentId: String) async throws {
        let authorCommentIds = getAuthorCommentIds(commentId: commentId)
        let params = PublicBlockFromCommentParams(commentIds: authorCommentIds.isEmpty ? nil : authorCommentIds)
        let response = try await PublicAPI.unBlockCommentPublic(
            tenantId: config.tenantId,
            commentId: commentId,
            publicBlockFromCommentParams: params,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(code: response.code, reason: response.reason, translatedError: response.translatedError)
        }

        setBlockedStateForAuthor(commentId: commentId, blocked: false)
    }

    private func getAuthorCommentIds(commentId: String) -> [String] {
        guard let renderable = commentsTree.commentsById[commentId] else { return [commentId] }
        let userId = renderable.comment.userId ?? renderable.comment.anonUserId
        guard let userId = userId, let userComments = commentsTree.commentsByUserId[userId] else {
            return [commentId]
        }
        return userComments.map { $0.comment.id }
    }

    /// Pin a comment. No-op if already pinned.
    public func pinComment(commentId: String) async throws {
        guard commentsTree.commentsById[commentId]?.comment.isPinned != true else { return }

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        let response = try await PublicAPI.pinComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        // Re-fetch after await — the renderable may have been replaced by a live event
        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isPinned = true
            renderable.objectWillChange.send()
        }
    }

    /// Unpin a comment. No-op if not pinned.
    public func unpinComment(commentId: String) async throws {
        guard commentsTree.commentsById[commentId]?.comment.isPinned == true else { return }

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        let response = try await PublicAPI.unPinComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isPinned = false
            renderable.objectWillChange.send()
        }
    }

    /// Lock a comment (prevent replies). No-op if already locked.
    public func lockComment(commentId: String) async throws {
        guard commentsTree.commentsById[commentId]?.comment.isLocked != true else { return }

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        let response = try await PublicAPI.lockComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isLocked = true
            renderable.objectWillChange.send()
        }
    }

    /// Unlock a comment (allow replies again). No-op if not locked.
    public func unlockComment(commentId: String) async throws {
        guard commentsTree.commentsById[commentId]?.comment.isLocked == true else { return }

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)
        let response = try await PublicAPI.unLockComment(
            tenantId: config.tenantId,
            commentId: commentId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard response.status == .success else {
            throw FastCommentsError(from: response)
        }

        if let renderable = commentsTree.commentsById[commentId] {
            renderable.comment.isLocked = false
            renderable.objectWillChange.send()
        }
    }

    // MARK: - Moderation Helpers

    private func setBlockedStateForAuthor(commentId: String, blocked: Bool) {
        guard let renderable = commentsTree.commentsById[commentId] else { return }
        let userId = renderable.comment.userId ?? renderable.comment.anonUserId
        guard let userId = userId else {
            renderable.comment.isBlocked = blocked
            renderable.objectWillChange.send()
            return
        }
        if let userComments = commentsTree.commentsByUserId[userId] {
            for comment in userComments {
                comment.comment.isBlocked = blocked
                comment.objectWillChange.send()
            }
        }
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
        if let broadcastId = event.broadcastId, broadcastIdsSent.contains(broadcastId) {
    
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
            guard let userId = event.userId,
                  let eventBadges = event.badges, !eventBadges.isEmpty else { break }

            let convertedBadges = eventBadges.compactMap { LiveEventHandler.toCommentUserBadgeInfo($0) }
            guard !convertedBadges.isEmpty else { break }

            let isCurrentUser = currentUser?.id != nil && currentUser?.id == userId

            if let userComments = commentsTree.commentsByUserId[userId], !userComments.isEmpty {
                // Determine which badges are new
                let existingBadges = userComments[0].comment.badges ?? []
                let existingIds = Set(existingBadges.map(\.id))
                let newBadges = convertedBadges.filter { !existingIds.contains($0.id) }

                // Update badges on all user's comments
                for comment in userComments {
                    comment.comment.badges = convertedBadges
                    comment.objectWillChange.send()
                }

                // Show badge award sheet for current user
                if isCurrentUser && !newBadges.isEmpty {
                    badgeAwardToShow = newBadges
                }
            } else if isCurrentUser {
                badgeAwardToShow = convertedBadges
            }
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

    private func processCommentsResponse(_ response: GetCommentsPublic200Response, isInitialLoad: Bool, clientHasMore: Bool? = nil) {
        commentsTree.build(comments: (response.comments ?? []))

        commentCountOnServer = response.commentCount ?? 0
        currentUser = response.user
        isSiteAdmin = response.isSiteAdmin ?? false
        hasBillingIssue = response.hasBillingIssue ?? false
        isDemo = response.isDemo ?? false
        hasMore = clientHasMore ?? (response.hasMore ?? false)
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
