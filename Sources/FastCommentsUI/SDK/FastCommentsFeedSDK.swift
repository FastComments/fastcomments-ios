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
    @Published public var newPostsCount: Int = 0

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
    private var myReacts: [String: [String: Bool]] = [:]
    private var lastPostId: String?
    private var webSocket: WebSocketClient?
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

        if !response.feedPosts.isEmpty {
            for post in response.feedPosts {
                postsById[post.id] = post
                if let reacts = post.reacts {
                    likeCounts[post.id] = reacts.values.reduce(0, +)
                }
            }
            feedPosts.append(contentsOf: response.feedPosts)
            lastPostId = response.feedPosts.last?.id
        }

        // Merge myReacts
        if let newReacts = response.myReacts {
            for (postId, reacts) in newReacts {
                myReacts[postId] = reacts
            }
        }

        hasMore = !response.feedPosts.isEmpty
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
            throw FastCommentsError(reason: "No post returned from server")
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
        myReacts.removeValue(forKey: postId)
        onPostDeleted?(postId)
    }

    // MARK: - Reactions

    /// Toggle a reaction on a feed post (optimistic update with rollback).
    public func reactPost(postId: String, reactionType: String = "like") async throws {
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

    // MARK: - Image Upload

    /// Upload a single image for a feed post. Uses multipart form upload.
    public func uploadImage(imageData: Data, filename: String) async throws -> FeedPostMediaItem {
        let boundary = UUID().uuidString
        let basePath = apiConfig.basePath
        let urlString = "\(basePath)/upload-image/\(config.tenantId)?urlId=FEEDS&sizePreset=CrossPlatform"
        guard let url = URL(string: urlString) else {
            throw FastCommentsError(reason: "Invalid upload URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let sso = config.sso {
            request.url = URL(string: urlString + "&sso=\(sso)")
        }

        // Build multipart body
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

        struct UploadResponse: Codable {
            let status: String
            let media: FeedPostMediaItem?
        }

        let uploadResponse = try JSONDecoder().decode(UploadResponse.self, from: data)
        guard let media = uploadResponse.media else {
            throw FastCommentsError(reason: "No media item returned from upload")
        }

        return media
    }

    /// Upload multiple images. Returns all successfully uploaded items.
    public func uploadImages(images: [(Data, String)]) async throws -> [FeedPostMediaItem] {
        try await withThrowingTaskGroup(of: FeedPostMediaItem.self) { group in
            for (data, filename) in images {
                group.addTask { try await self.uploadImage(imageData: data, filename: filename) }
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
    public func fetchPostStats(postIds: [String]) async throws {
        guard !postIds.isEmpty else { return }

        let response = try await PublicAPI.getFeedPostsStats(
            tenantId: config.tenantId,
            postIds: postIds,
            sso: config.sso,
            apiConfiguration: apiConfig
        )

        for (postId, stats) in response.stats {
            if let reacts = stats.reacts {
                likeCounts[postId] = reacts.values.reduce(0, +)
            }
            if let commentCount = stats.commentCount, var post = postsById[postId] {
                post = FeedPost(
                    id: post.id, tenantId: post.tenantId, title: post.title,
                    fromUserId: post.fromUserId, fromUserDisplayName: post.fromUserDisplayName,
                    fromUserAvatar: post.fromUserAvatar, fromIpHash: post.fromIpHash,
                    tags: post.tags, weight: post.weight, meta: post.meta,
                    contentHTML: post.contentHTML, media: post.media, links: post.links,
                    createdAt: post.createdAt, reacts: stats.reacts ?? post.reacts,
                    commentCount: commentCount
                )
                postsById[postId] = post
                if let idx = feedPosts.firstIndex(where: { $0.id == postId }) {
                    feedPosts[idx] = post
                }
            }
        }
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
            likeCounts: likeCounts
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

        postsById.removeAll()
        for post in feedPosts {
            postsById[post.id] = post
        }
    }

    // MARK: - Bridge to Comments

    /// Create a FastCommentsSDK configured for viewing comments on a specific feed post.
    public func createCommentsSDK(for post: FeedPost) -> FastCommentsSDK {
        var commentConfig = config
        commentConfig.urlId = post.id
        return FastCommentsSDK(config: commentConfig)
    }

    // MARK: - Cleanup

    public func cleanup() {
        webSocket?.disconnect()
        webSocket = nil
        statsPollTask?.cancel()
        statsPollTask = nil
    }

    // MARK: - Live Events (Internal)

    func subscribeToLiveEvents() {
        webSocket?.disconnect()

        guard let tenantIdWS = tenantIdWS,
              let urlIdWS = urlIdWS else { return }

        let ws = WebSocketClient()
        ws.onEvent = { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleLiveEvent(event)
            }
        }
        ws.connect(
            tenantIdWS: tenantIdWS,
            urlIdWS: urlIdWS,
            userIdWS: userIdWS,
            basePath: apiConfig.basePath
        )
        webSocket = ws
    }

    func handleLiveEvent(_ event: LiveEvent) {
        if let broadcastId = event.broadcastId, broadcastIdsSent.remove(broadcastId) != nil {
            return
        }

        switch event.type {
        case .newFeedPost:
            if let post = event.feedPost {
                postsById[post.id] = post
                feedPosts.insert(post, at: 0)
                if let reacts = post.reacts {
                    likeCounts[post.id] = reacts.values.reduce(0, +)
                }
            }
        case .updatedFeedPost:
            if let post = event.feedPost {
                postsById[post.id] = post
                if let idx = feedPosts.firstIndex(where: { $0.id == post.id }) {
                    feedPosts[idx] = post
                }
                if let reacts = post.reacts {
                    likeCounts[post.id] = reacts.values.reduce(0, +)
                }
            }
        case .deletedFeedPost:
            if let post = event.feedPost {
                postsById.removeValue(forKey: post.id)
                feedPosts.removeAll { $0.id == post.id }
                likeCounts.removeValue(forKey: post.id)
                myReacts.removeValue(forKey: post.id)
                onPostDeleted?(post.id)
            }
        default:
            break
        }
    }

    // MARK: - Private

    private func processFeedResponse(_ response: GetFeedPostsPublic200Response, isInitialLoad: Bool) {
        if isInitialLoad {
            feedPosts = response.feedPosts
            postsById.removeAll()
            likeCounts.removeAll()
        } else {
            feedPosts = response.feedPosts
            postsById.removeAll()
        }

        for post in response.feedPosts {
            postsById[post.id] = post
            if let reacts = post.reacts {
                likeCounts[post.id] = reacts.values.reduce(0, +)
            }
        }

        if let newReacts = response.myReacts {
            myReacts = newReacts
        }

        currentUser = response.user
        lastPostId = response.feedPosts.last?.id
        hasMore = !response.feedPosts.isEmpty

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
