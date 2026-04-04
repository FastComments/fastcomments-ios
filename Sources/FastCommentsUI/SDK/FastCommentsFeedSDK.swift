import Foundation
import Combine
import FastCommentsSwift

/// SDK for the FastComments social feed system.
/// Manages feed posts, reactions, image uploads, and live events.
/// Mirrors FastCommentsFeedSDK.java from Android.
@MainActor
public final class FastCommentsFeedSDK: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var feedPosts: [FeedPost] = []
    @Published public private(set) var hasMore: Bool = false
    @Published public private(set) var currentUser: UserSessionInfo?
    @Published public private(set) var blockingErrorMessage: String?
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var newPostsCount: Int = 0

    // MARK: - Public Properties

    public let config: FastCommentsWidgetConfig
    public var theme: FastCommentsTheme?
    public var tagSupplier: (any TagSupplier)?
    public var pageSize: Int = 10
    public var onPostDeleted: ((String) -> Void)?
    public var globalFeedToolbarButtons: [any FeedCustomToolbarButton] = []

    // MARK: - Internal State

    var broadcastIdsSent: Set<String> = []
    private let apiConfig: FastCommentsSwiftAPIConfiguration
    private var postsById: [String: FeedPost] = [:]
    private var likeCounts: [String: Int] = [:]
    private var commentCounts: [String: Int] = [:]
    private var myReacts: [String: [String: Bool]] = [:]
    private var lastPostId: String?
    private let liveEventSubscriber = LiveEventSubscriber()
    private var liveEventSubscription: SubscribeToChangesResult?
    private var tenantIdWS: String?
    private var urlIdWS: String?
    private var userIdWS: String?
    private var statsPollTask: Task<Void, Never>?

    // MARK: - Init

    public init(config: FastCommentsWidgetConfig) {
        self.config = config
        self.apiConfig = FastCommentsSwiftAPIConfiguration(
            basePath: FastCommentsSDK.getAPIBasePath(config: config)
        )
    }

    // MARK: - Load & Paginate

    /// Initial load of feed posts. Sets up live events and stats polling.
    @discardableResult
    public func load() async throws -> GetFeedPostsPublic200Response {
        isLoading = true
        defer { isLoading = false }

        let tags = tagSupplier?.getTags(currentUser: currentUser)

        let response = try await PublicAPI.getFeedPostsPublic(
            tenantId: config.tenantId,
            limit: pageSize,
            tags: tags,
            sso: config.sso,
            includeUserInfo: true,
            apiConfiguration: apiConfig
        )

        processFeedResponse(response, isInitialLoad: true)
        return response
    }

    /// Load next page of feed posts (cursor-based via afterId).
    @discardableResult
    public func loadMore() async throws -> GetFeedPostsPublic200Response {
        guard let lastId = lastPostId else {
            throw FastCommentsError(reason: "No cursor available for loading more posts")
        }

        isLoading = true
        defer { isLoading = false }

        let tags = tagSupplier?.getTags(currentUser: currentUser)

        let response = try await PublicAPI.getFeedPostsPublic(
            tenantId: config.tenantId,
            afterId: lastId,
            limit: pageSize,
            tags: tags,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        if !(response.feedPosts ?? []).isEmpty {
            for post in (response.feedPosts ?? []) {
                postsById[post.id] = post
                if let reacts = post.reacts {
                    likeCounts[post.id] = reacts.values.reduce(0, +)
                }
                if let cc = post.commentCount {
                    commentCounts[post.id] = cc
                }
            }
            feedPosts.append(contentsOf: (response.feedPosts ?? []))
            lastPostId = (response.feedPosts ?? []).last?.id
        }

        // Merge myReacts
        if let newReacts = response.myReacts {
            for (postId, reacts) in newReacts {
                myReacts[postId] = reacts
            }
        }

        hasMore = !(response.feedPosts ?? []).isEmpty
        return response
    }

    /// Pull-to-refresh: reload the most recent posts.
    @discardableResult
    public func refresh() async throws -> GetFeedPostsPublic200Response {
        let tags = tagSupplier?.getTags(currentUser: currentUser)

        let response = try await PublicAPI.getFeedPostsPublic(
            tenantId: config.tenantId,
            limit: pageSize,
            tags: tags,
            sso: config.sso,
            includeUserInfo: true,
            apiConfiguration: apiConfig
        )

        processFeedResponse(response, isInitialLoad: false)
        return response
    }

    /// Load new posts that arrived via live events.
    /// Fetches the latest page and prepends any posts not already in the feed,
    /// preserving the user's existing loaded content and pagination cursor.
    @discardableResult
    public func loadNewPosts() async throws -> GetFeedPostsPublic200Response {
        guard newPostsCount > 0 else {
            throw FastCommentsError(reason: "No new posts to load")
        }

        let tags = tagSupplier?.getTags(currentUser: currentUser)

        let response: GetFeedPostsPublic200Response
        do {
            response = try await PublicAPI.getFeedPostsPublic(
                tenantId: config.tenantId,
                limit: pageSize,
                tags: tags,
                sso: config.sso,
                includeUserInfo: true,
                apiConfiguration: apiConfig
            )
        } catch {
            // Count stays so the banner remains visible on failure
            throw error
        }

        newPostsCount = 0

        // Prepend only posts that aren't already in the feed
        let newPosts = (response.feedPosts ?? []).filter { postsById[$0.id] == nil }
        for post in newPosts {
            postsById[post.id] = post
            if let reacts = post.reacts {
                likeCounts[post.id] = reacts.values.reduce(0, +)
            }
            if let cc = post.commentCount {
                commentCounts[post.id] = cc
            }
        }
        if !newPosts.isEmpty {
            feedPosts.insert(contentsOf: newPosts, at: 0)
        }

        // Merge myReacts from fresh response
        if let newReacts = response.myReacts {
            for (postId, reacts) in newReacts {
                myReacts[postId] = reacts
            }
        }

        if let user = response.user {
            currentUser = user
        }

        return response
    }

    // MARK: - Post CRUD

    /// Create a new feed post.
    @discardableResult
    public func createPost(params: CreateFeedPostParams) async throws -> FeedPost {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let response = try await PublicAPI.createFeedPostPublic(
            tenantId: config.tenantId,
            createFeedPostParams: params,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        guard let post = response.feedPost else {
            throw FastCommentsError(reason: "No post returned from API")
        }

        // Insert at top of feed
        postsById[post.id] = post
        feedPosts.insert(post, at: 0)
        return post
    }

    /// Delete a feed post.
    public func deletePost(postId: String) async throws {
        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        _ = try await PublicAPI.deleteFeedPostPublic(
            tenantId: config.tenantId,
            postId: postId,
            broadcastId: broadcastId,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        postsById.removeValue(forKey: postId)
        feedPosts.removeAll { $0.id == postId }
        likeCounts.removeValue(forKey: postId)
        commentCounts.removeValue(forKey: postId)
        myReacts.removeValue(forKey: postId)
        onPostDeleted?(postId)
    }

    // MARK: - Reactions

    /// Toggle a reaction on a feed post (optimistic update with rollback).
    public func reactPost(postId: String, reactionType: String = "l") async throws {
        let isUndo = hasUserReacted(postId: postId, reactType: reactionType)

        // Optimistic update
        if isUndo {
            myReacts[postId]?.removeValue(forKey: reactionType)
            likeCounts[postId] = max(0, (likeCounts[postId] ?? 0) - 1)
        } else {
            myReacts[postId, default: [:]][reactionType] = true
            likeCounts[postId] = (likeCounts[postId] ?? 0) + 1
        }
        objectWillChange.send()

        let broadcastId = UUID().uuidString
        broadcastIdsSent.insert(broadcastId)

        let params = ReactBodyParams(reactType: reactionType)

        do {
            _ = try await PublicAPI.reactFeedPostPublic(
                tenantId: config.tenantId,
                postId: postId,
                reactBodyParams: params,
                isUndo: isUndo,
                broadcastId: broadcastId,
                sso: config.sso,
                apiConfiguration: apiConfig
            )
        } catch {
            // Rollback on failure
            if isUndo {
                myReacts[postId, default: [:]][reactionType] = true
                likeCounts[postId] = (likeCounts[postId] ?? 0) + 1
            } else {
                myReacts[postId]?.removeValue(forKey: reactionType)
                likeCounts[postId] = max(0, (likeCounts[postId] ?? 0) - 1)
            }
            objectWillChange.send()
            throw error
        }
    }

    /// Check if the current user has reacted to a post with a specific type.
    public func hasUserReacted(postId: String, reactType: String) -> Bool {
        myReacts[postId]?[reactType] ?? false
    }

    /// Get the like count for a post.
    public func getLikeCount(postId: String) -> Int {
        likeCounts[postId] ?? 0
    }

    /// Get the comment count for a post.
    public func getCommentCount(postId: String) -> Int {
        commentCounts[postId] ?? 0
    }

    // MARK: - Image Upload

    /// Upload a single image for a feed post using the generated API.
    public func uploadImage(fileURL: URL) async throws -> FeedPostMediaItem {
        let response = try await PublicAPI.uploadImage(
            tenantId: config.tenantId,
            file: fileURL,
            sizePreset: .crossPlatform,
            urlId: "FEEDS",
            apiConfiguration: apiConfig
        )

        guard let assets = response.media, !assets.isEmpty else {
            throw FastCommentsError(reason: "No media item returned from upload")
        }

        return FeedPostMediaItem(
            sizes: assets.map { FeedPostMediaItemAsset(w: $0.w, h: $0.h, src: $0.src) }
        )
    }

    /// Upload multiple images. Returns all successfully uploaded items.
    public func uploadImages(fileURLs: [URL]) async throws -> [FeedPostMediaItem] {
        try await withThrowingTaskGroup(of: FeedPostMediaItem.self) { group in
            for url in fileURLs {
                group.addTask { try await self.uploadImage(fileURL: url) }
            }
            var results: [FeedPostMediaItem] = []
            for try await item in group {
                results.append(item)
            }
            return results
        }
    }

    // MARK: - Stats Polling

    /// Fetch updated stats for currently visible posts.
    /// Updates side dictionaries only — does not replace posts in the feedPosts array,
    /// so ForEach identity is preserved and scroll is not interrupted.
    public func fetchPostStats(postIds: [String]) async throws {
        guard !postIds.isEmpty else { return }

        let response = try await PublicAPI.getFeedPostsStats(
            tenantId: config.tenantId,
            postIds: postIds,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        for (postId, stats) in (response.stats ?? [:]) {
            if let reacts = stats.reacts {
                likeCounts[postId] = reacts.values.reduce(0, +)
            }
            if let commentCount = stats.commentCount {
                commentCounts[postId] = commentCount
            }
        }
        objectWillChange.send()
    }

    // MARK: - State Serialization

    public func savePaginationState() -> FeedState {
        FeedState(
            lastPostId: lastPostId,
            hasMore: hasMore,
            pageSize: pageSize,
            newPostsCount: newPostsCount,
            feedPosts: feedPosts,
            myReacts: myReacts,
            likeCounts: likeCounts,
            commentCounts: commentCounts
        )
    }

    public func restorePaginationState(_ state: FeedState) {
        lastPostId = state.lastPostId
        hasMore = state.hasMore
        pageSize = state.pageSize
        newPostsCount = state.newPostsCount
        feedPosts = state.feedPosts
        myReacts = state.myReacts
        likeCounts = state.likeCounts
        commentCounts = state.commentCounts

        postsById.removeAll()
        for post in feedPosts {
            postsById[post.id] = post
        }
    }

    // MARK: - Bridge to Comments

    /// Create a FastCommentsSDK configured for viewing comments on a specific feed post.
    public func createCommentsSDK(for post: FeedPost) -> FastCommentsSDK {
        var commentConfig = config
        commentConfig.urlId = "post:" + post.id
        return FastCommentsSDK(config: commentConfig)
    }

    // MARK: - Cleanup

    public func cleanup() {
        liveEventSubscription?.close()
        liveEventSubscription = nil
        statsPollTask?.cancel()
        statsPollTask = nil
    }

    // MARK: - Live Events (Internal)

    func subscribeToLiveEvents() {
        liveEventSubscription?.close()

        guard let _ = tenantIdWS,
              let urlIdWS = urlIdWS else { return }

        let liveConfig = LiveEventConfig(
            tenantId: config.tenantId,
            urlId: config.urlId,
            urlIdWS: urlIdWS,
            userIdWS: userIdWS ?? "",
            region: config.region
        )

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
        if let broadcastId = event.broadcastId, broadcastIdsSent.remove(broadcastId) != nil {
            return
        }

        switch event.type {
        case .newFeedPost:
            if event.feedPost != nil {
                newPostsCount += 1
            }
        case .updatedFeedPost:
            if let pubSubPost = event.feedPost, let post = Self.toFeedPost(pubSubPost) {
                // Always update stats in side dictionaries
                if let reacts = post.reacts {
                    likeCounts[post.id] = reacts.values.reduce(0, +)
                }
                if let cc = post.commentCount {
                    commentCounts[post.id] = cc
                }
                // Check if non-stats content changed
                let existing = postsById[post.id]
                let contentChanged = existing == nil
                    || existing?.title != post.title
                    || existing?.contentHTML != post.contentHTML
                    || existing?.media != post.media
                    || existing?.links != post.links
                    || existing?.fromUserDisplayName != post.fromUserDisplayName
                    || existing?.fromUserAvatar != post.fromUserAvatar
                    || existing?.fromUserId != post.fromUserId
                    || existing?.tags != post.tags
                    || existing?.weight != post.weight
                    || existing?.meta != post.meta
                    || existing?.fromIpHash != post.fromIpHash
                if contentChanged {
                    postsById[post.id] = post
                    if let idx = feedPosts.firstIndex(where: { $0.id == post.id }) {
                        feedPosts[idx] = post
                    }
                }
            }
        case .deletedFeedPost:
            if let postId = event.feedPost?.id {
                postsById.removeValue(forKey: postId)
                feedPosts.removeAll { $0.id == postId }
                likeCounts.removeValue(forKey: postId)
                commentCounts.removeValue(forKey: postId)
                myReacts.removeValue(forKey: postId)
                onPostDeleted?(postId)
            } else {
                // Server didn't include post ID; refresh to discover removal
                Task { [weak self] in try? await self?.refresh() }
            }
        default:
            break
        }
    }

    // MARK: - Private

    private func processFeedResponse(_ response: GetFeedPostsPublic200Response, isInitialLoad: Bool) {
        feedPosts = (response.feedPosts ?? [])
        postsById.removeAll()
        likeCounts.removeAll()
        commentCounts.removeAll()

        for post in (response.feedPosts ?? []) {
            postsById[post.id] = post
            if let reacts = post.reacts {
                likeCounts[post.id] = reacts.values.reduce(0, +)
            }
            if let cc = post.commentCount {
                commentCounts[post.id] = cc
            }
        }

        if let newReacts = response.myReacts {
            myReacts = newReacts
        }

        currentUser = response.user
        lastPostId = (response.feedPosts ?? []).last?.id
        hasMore = !(response.feedPosts ?? []).isEmpty

        // Extract WebSocket params
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

        // Check for blocking errors
        if let error = response.translatedError {
            blockingErrorMessage = error
        }

        // Start stats polling
        startStatsPolling()
    }

    private static func toFeedPost(_ pubSub: PubSubFeedPost) -> FeedPost? {
        guard let id = pubSub.id, let tenantId = pubSub.tenantId else { return nil }
        let dateFormatter = ISO8601DateFormatter()
        return FeedPost(
            id: id,
            tenantId: tenantId,
            title: pubSub.title,
            fromUserId: pubSub.fromUserId,
            fromUserDisplayName: pubSub.fromUserDisplayName,
            fromUserAvatar: pubSub.fromUserAvatar,
            fromIpHash: pubSub.fromIpHash,
            tags: pubSub.tags,
            weight: pubSub.weight,
            meta: pubSub.meta,
            contentHTML: pubSub.contentHTML,
            media: pubSub.media?.compactMap { Self.toFeedPostMediaItem($0) },
            links: pubSub.links?.compactMap { Self.toFeedPostLink($0) },
            createdAt: pubSub.createdAt.flatMap { dateFormatter.date(from: $0) } ?? Date(),
            reacts: pubSub.reacts,
            commentCount: pubSub.commentCount
        )
    }

    private static func toFeedPostMediaItem(_ pubSub: PubSubFeedPostMediaItem) -> FeedPostMediaItem? {
        let sizes = pubSub.sizes?.compactMap { asset -> FeedPostMediaItemAsset? in
            guard let w = asset.w, let h = asset.h, let src = asset.src else { return nil }
            return FeedPostMediaItemAsset(w: w, h: h, src: src)
        } ?? []
        return FeedPostMediaItem(title: pubSub.title, linkUrl: pubSub.linkUrl, sizes: sizes)
    }

    private static func toFeedPostLink(_ pubSub: PubSubFeedPostLink) -> FeedPostLink {
        FeedPostLink(text: pubSub.text, title: pubSub.title, description: pubSub.description, url: pubSub.url)
    }

    private func startStatsPolling() {
        statsPollTask?.cancel()
        statsPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
                guard let self = self, !Task.isCancelled else { break }
                let postIds = Array(self.postsById.keys)
                try? await self.fetchPostStats(postIds: postIds)
            }
        }
    }
}
