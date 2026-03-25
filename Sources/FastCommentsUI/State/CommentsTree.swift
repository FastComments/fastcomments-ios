import Foundation
import Combine
import FastCommentsSwift

/// Hierarchical comment tree managing all comments and the flat visible-node list
/// that drives SwiftUI rendering. Mirrors CommentsTree.java from Android.
@MainActor
public final class CommentsTree: ObservableObject {
    /// The flat list of visible nodes. SwiftUI ForEach binds to this.
    @Published public private(set) var visibleNodes: [RenderableNode] = []

    /// All comments indexed by ID for O(1) lookup.
    public var commentsById: [String: RenderableComment] = [:]
    /// Comments indexed by userId for presence updates.
    public var commentsByUserId: [String: [RenderableComment]] = [:]
    /// All comments in insertion order.
    public var allComments: [RenderableComment] = []
    /// Whether to insert date separators (live chat mode).
    public var liveChatStyle: Bool = false

    /// Called when presence needs to be fetched for newly visible user IDs.
    public var onPresenceNeeded: (([String]) -> Void)?

    // Buffered comments when showLiveRightAway is false
    private var newRootComments: [PublicComment] = []
    private var newRootCommentsButton: RenderableButton?
    private var newChildCommentsButtons: [String: RenderableButton] = [:]

    public init() {}

    // MARK: - Build & Populate

    /// Build the tree from an initial set of comments (first page load).
    public func build(comments: [PublicComment]) {
        commentsById.removeAll()
        commentsByUserId.removeAll()
        allComments.removeAll()
        newRootComments.removeAll()
        newRootCommentsButton = nil
        newChildCommentsButtons.removeAll()

        var newAllComments: [RenderableComment] = []
        var newVisibleNodes: [RenderableNode] = []

        guard !comments.isEmpty else {
            visibleNodes = []
            return
        }

        if !liveChatStyle {
            for comment in comments {
                let renderable = RenderableComment(comment: comment)
                addToMapAndRelated(renderable)
                newAllComments.append(renderable)
                newVisibleNodes.append(renderable)
                if let children = comment.children, !children.isEmpty {
                    handleChildren(
                        allComments: &newAllComments,
                        visibleNodes: &newVisibleNodes,
                        comments: children,
                        visible: renderable.isRepliesShown
                    )
                }
            }
        } else {
            var currentDateComponents: DateComponents?
            let calendar = Calendar.current

            for comment in comments {
                let renderable = RenderableComment(comment: comment)
                addToMapAndRelated(renderable)
                newAllComments.append(renderable)

                if let date = comment.date {
                    let commentComponents = calendar.dateComponents([.year, .month, .day], from: date)
                    if currentDateComponents == nil || currentDateComponents != commentComponents {
                        currentDateComponents = commentComponents
                        newVisibleNodes.append(DateSeparator(date: date))
                    }
                }

                newVisibleNodes.append(renderable)

                if let children = comment.children, !children.isEmpty {
                    handleChildren(
                        allComments: &newAllComments,
                        visibleNodes: &newVisibleNodes,
                        comments: children,
                        visible: renderable.isRepliesShown
                    )
                }
            }
        }

        allComments = newAllComments
        visibleNodes = newVisibleNodes
    }

    /// Append comments from pagination (next page).
    public func appendComments(_ comments: [PublicComment]) {
        guard !comments.isEmpty else { return }

        var updatedNodes = visibleNodes

        for comment in comments {
            guard commentsById[comment.id] == nil else { continue }
            let renderable = RenderableComment(comment: comment)
            addToMapAndRelated(renderable)
            allComments.append(renderable)
            updatedNodes.append(renderable)
            if let children = comment.children, !children.isEmpty {
                handleChildren(
                    allComments: &allComments,
                    visibleNodes: &updatedNodes,
                    comments: children,
                    visible: renderable.isRepliesShown
                )
            }
        }

        visibleNodes = updatedNodes
    }

    /// Add children for a parent comment (child pagination / lazy load).
    public func addForParent(parentId: String?, comments: [PublicComment]) {
        let parent = parentId != nil ? commentsById[parentId!] : nil

        if let parent = parent {
            // Update hasMoreChildren
            if let childCount = parent.comment.childCount {
                let currentChildren = parent.comment.children?.count ?? 0
                parent.hasMoreChildren = (currentChildren + comments.count) < childCount
            }
        }

        for comment in comments {
            let childRenderable = RenderableComment(comment: comment)
            addToMapAndRelated(childRenderable)
            allComments.append(childRenderable)
        }
    }

    // MARK: - Live Updates

    /// Add a new comment from a live event.
    public func addComment(_ comment: PublicComment, displayNow: Bool, sortDirection: SortDirections? = .nf) {
        guard commentsById[comment.id] == nil else { return }

        let renderable = RenderableComment(comment: comment)
        addToMapAndRelated(renderable)

        let isNewestFirst = sortDirection == .nf || sortDirection == .mr

        if comment.parentId == nil {
            // Root comment
            if isNewestFirst {
                allComments.insert(renderable, at: 0)
            } else {
                allComments.append(renderable)
            }

            if displayNow {
                var updatedNodes = visibleNodes

                if isNewestFirst {
                    updatedNodes.insert(renderable, at: 0)
                } else {
                    // For oldest-first (chat), add at bottom with optional date separator
                    if liveChatStyle, let date = comment.date {
                        let calendar = Calendar.current
                        let commentComponents = calendar.dateComponents([.year, .month, .day], from: date)
                        var needDateSeparator = true

                        // Check if previous comment/separator is from the same date
                        for i in stride(from: updatedNodes.count - 1, through: 0, by: -1) {
                            let node = updatedNodes[i]
                            if let separator = node as? DateSeparator {
                                let sepComponents = calendar.dateComponents([.year, .month, .day], from: separator.date)
                                needDateSeparator = sepComponents != commentComponents
                                break
                            } else if let lastComment = node as? RenderableComment,
                                      let lastDate = lastComment.comment.date {
                                let lastComponents = calendar.dateComponents([.year, .month, .day], from: lastDate)
                                needDateSeparator = lastComponents != commentComponents
                                break
                            }
                        }

                        if needDateSeparator {
                            updatedNodes.append(DateSeparator(date: date))
                        }
                    }
                    updatedNodes.append(renderable)
                }

                visibleNodes = updatedNodes
                requestPresenceForComment(renderable)
            } else {
                // Buffer and show "new comments" button
                newRootComments.append(comment)
                var updatedNodes = visibleNodes

                if newRootCommentsButton == nil {
                    let button = RenderableButton(
                        buttonType: .newRootComments,
                        commentCount: newRootComments.count
                    )
                    newRootCommentsButton = button
                    updatedNodes.insert(button, at: 0)
                } else if let existingButton = newRootCommentsButton,
                          let buttonIndex = updatedNodes.firstIndex(where: { $0.id == existingButton.id }) {
                    let newButton = RenderableButton(
                        buttonType: .newRootComments,
                        commentCount: newRootComments.count
                    )
                    newRootCommentsButton = newButton
                    updatedNodes[buttonIndex] = newButton
                }

                visibleNodes = updatedNodes
            }
        } else {
            // Reply to existing comment
            guard let parent = commentsById[comment.parentId!] else { return }

            let parentIndex = visibleNodes.firstIndex(where: { $0.id == parent.id })

            if parent.isRepliesShown && displayNow {
                var updatedNodes = visibleNodes
                let insertionIndex = findLastChildIndex(parent, in: updatedNodes) + 1
                updatedNodes.insert(renderable, at: insertionIndex)
                visibleNodes = updatedNodes
                requestPresenceForComment(renderable)
            } else if parent.isRepliesShown {
                // Buffer as new child comment
                parent.addNewChildComment(comment)
                updateNewChildCommentsButton(for: parent)
            }

            // Re-trigger UI update for parent (reply count changed)
            if parentIndex != nil {
                parent.objectWillChange.send()
            }
        }
    }

    /// Remove a comment by ID (from live event or delete action).
    public func removeComment(commentId: String) {
        guard let renderable = commentsById[commentId] else { return }

        // Remove from maps
        commentsById.removeValue(forKey: commentId)
        allComments.removeAll { $0.id == commentId }

        // Remove from visible nodes (including any children)
        var updatedNodes = visibleNodes
        updatedNodes.removeAll { $0.id == commentId }

        // Recursively remove children
        if let children = renderable.comment.children {
            removeChildrenFromNodes(children, nodes: &updatedNodes)
        }

        visibleNodes = updatedNodes
    }

    /// Update a comment in-place (from live event).
    public func updateComment(_ comment: PublicComment) {
        // The generated PublicComment is a struct, so we replace the renderable.
        // Since RenderableComment.comment is let, we need to create a new one.
        guard let existing = commentsById[comment.id] else { return }
        // Transfer UI state to a new renderable
        let updated = RenderableComment(comment: comment)
        updated.isRepliesShown = existing.isRepliesShown
        updated.isOnline = existing.isOnline
        updated.hasMoreChildren = existing.hasMoreChildren
        updated.isLoadingChildren = existing.isLoadingChildren
        updated.childSkip = existing.childSkip
        updated.childPage = existing.childPage
        updated.childPageSize = existing.childPageSize
        updated.newChildComments = existing.newChildComments

        commentsById[comment.id] = updated
        if let allIdx = allComments.firstIndex(where: { $0.id == comment.id }) {
            allComments[allIdx] = updated
        }

        var updatedNodes = visibleNodes
        if let visIdx = updatedNodes.firstIndex(where: { $0.id == comment.id }) {
            updatedNodes[visIdx] = updated
        }
        visibleNodes = updatedNodes
    }

    // MARK: - Reply Toggling

    /// Toggle reply visibility for a comment. If children aren't loaded yet,
    /// calls getChildren to fetch them asynchronously.
    public func toggleRepliesVisible(
        _ renderableComment: RenderableComment,
        getChildren: ((GetChildrenRequest) async throws -> [PublicComment])?
    ) async {
        let newState = !renderableComment.isRepliesShown
        renderableComment.isRepliesShown = newState

        if newState {
            // Show replies
            let children = renderableComment.comment.children
            if let children = children, !children.isEmpty {
                insertChildrenAfter(renderableComment, children: children)
            } else if renderableComment.comment.hasChildren == true {
                // Need to fetch children
                renderableComment.resetChildPagination()
                renderableComment.isLoadingChildren = true

                let request = GetChildrenRequest(
                    parentId: renderableComment.comment.id,
                    skip: 0,
                    limit: renderableComment.childPageSize,
                    isLoadMore: false
                )

                do {
                    if let fetchedChildren = try await getChildren?(request) {
                        renderableComment.isLoadingChildren = false
                        addForParent(parentId: renderableComment.comment.id, comments: fetchedChildren)
                        insertChildrenAfter(renderableComment, children: fetchedChildren)

                        if let childCount = renderableComment.comment.childCount {
                            renderableComment.hasMoreChildren = fetchedChildren.count < childCount
                        }
                    }
                } catch {
                    renderableComment.isLoadingChildren = false
                }
            }
        } else {
            // Hide replies
            let parentId = renderableComment.comment.id

            // Remove new-child button if present
            if let button = newChildCommentsButtons.removeValue(forKey: parentId) {
                var updatedNodes = visibleNodes
                updatedNodes.removeAll { $0.id == button.id }
                visibleNodes = updatedNodes
            }

            // Hide children
            if let children = renderableComment.comment.children {
                var updatedNodes = visibleNodes
                hideChildrenFromNodes(children, nodes: &updatedNodes)
                visibleNodes = updatedNodes
            }

            renderableComment.resetChildPagination()
        }
    }

    // MARK: - Buffered Comment Display

    /// Display all buffered root comments (triggered by tapping "Show N new comments" button).
    public func showNewRootComments() {
        guard !newRootComments.isEmpty else { return }

        var updatedNodes = visibleNodes

        // Remove the button
        if let button = newRootCommentsButton {
            updatedNodes.removeAll { $0.id == button.id }
            newRootCommentsButton = nil
        }

        // Add all buffered comments
        for comment in newRootComments {
            if commentsById[comment.id] == nil {
                let renderable = RenderableComment(comment: comment)
                addToMapAndRelated(renderable)
                allComments.insert(renderable, at: 0)
                updatedNodes.insert(renderable, at: 0)
            }
        }

        newRootComments.removeAll()
        visibleNodes = updatedNodes
    }

    /// Display buffered child comments for a parent.
    public func showNewChildComments(parentId: String) {
        guard let parent = commentsById[parentId] else { return }
        guard let newChildren = parent.getAndClearNewChildComments(), !newChildren.isEmpty else { return }

        var updatedNodes = visibleNodes

        // Remove the "new child comments" button
        if let button = newChildCommentsButtons.removeValue(forKey: parentId) {
            updatedNodes.removeAll { $0.id == button.id }
        }

        // Insert the buffered children after the parent's last visible child
        let insertionIndex = findLastChildIndex(parent, in: updatedNodes) + 1

        for (offset, comment) in newChildren.enumerated() {
            if commentsById[comment.id] == nil {
                let renderable = RenderableComment(comment: comment)
                addToMapAndRelated(renderable)
                allComments.append(renderable)
                updatedNodes.insert(renderable, at: insertionIndex + offset)
            }
        }

        visibleNodes = updatedNodes
    }

    // MARK: - Presence

    /// Update online status for all comments by a given user.
    public func updateUserPresence(userId: String, isOnline: Bool) {
        guard let comments = commentsByUserId[userId] else { return }
        for comment in comments {
            comment.isOnline = isOnline
        }
    }

    // MARK: - Counts

    public func totalSize() -> Int { allComments.count }
    public func visibleSize() -> Int { visibleNodes.count }

    // MARK: - Private Helpers

    private func addToMapAndRelated(_ renderable: RenderableComment) {
        commentsById[renderable.comment.id] = renderable
        if let userId = renderable.comment.userId {
            commentsByUserId[userId, default: []].append(renderable)
        }
        if let anonUserId = renderable.comment.anonUserId {
            commentsByUserId[anonUserId, default: []].append(renderable)
        }
    }

    private func handleChildren(
        allComments: inout [RenderableComment],
        visibleNodes: inout [RenderableNode],
        comments: [PublicComment],
        visible: Bool
    ) {
        for child in comments {
            let childRenderable = RenderableComment(comment: child)
            addToMapAndRelated(childRenderable)
            allComments.append(childRenderable)
            let childrenVisible = visible && childRenderable.isRepliesShown
            if childrenVisible {
                visibleNodes.append(childRenderable)
            }
            if let grandchildren = child.children, !grandchildren.isEmpty {
                handleChildren(
                    allComments: &allComments,
                    visibleNodes: &visibleNodes,
                    comments: grandchildren,
                    visible: childrenVisible
                )
            }
        }
    }

    private func insertChildrenAfter(_ parent: RenderableComment, children: [PublicComment]) {
        var updatedNodes = visibleNodes
        guard let parentIndex = updatedNodes.firstIndex(where: { $0.id == parent.id }) else { return }

        let insertStart = parentIndex + 1
        for (offset, child) in children.enumerated() {
            if let childRenderable = commentsById[child.id] {
                updatedNodes.insert(childRenderable, at: insertStart + offset)
            }
        }
        visibleNodes = updatedNodes

        // Request presence for newly visible users
        let userIds = children.compactMap { $0.userId ?? $0.anonUserId }
        if !userIds.isEmpty {
            onPresenceNeeded?(userIds)
        }
    }

    private func findLastChildIndex(_ parent: RenderableComment, in nodes: [RenderableNode]) -> Int {
        guard let parentIndex = nodes.firstIndex(where: { $0.id == parent.id }) else {
            return nodes.count - 1
        }

        let parentId = parent.comment.id
        var lastChildIndex = parentIndex

        for i in (parentIndex + 1)..<nodes.count {
            let node = nodes[i]
            if let comment = node as? RenderableComment {
                if comment.comment.parentId != parentId {
                    break
                }
                lastChildIndex = i
            } else if let button = node as? RenderableButton {
                if button.buttonType == .newChildComments && button.parentId == parentId {
                    lastChildIndex = i
                } else {
                    break
                }
            } else {
                break
            }
        }

        return lastChildIndex
    }

    private func hideChildrenFromNodes(_ children: [PublicComment], nodes: inout [RenderableNode]) {
        for child in children {
            nodes.removeAll { $0.id == child.id }
            if let grandchildren = child.children {
                hideChildrenFromNodes(grandchildren, nodes: &nodes)
            }
        }
    }

    private func removeChildrenFromNodes(_ children: [PublicComment], nodes: inout [RenderableNode]) {
        for child in children {
            commentsById.removeValue(forKey: child.id)
            allComments.removeAll { $0.id == child.id }
            nodes.removeAll { $0.id == child.id }
            if let grandchildren = child.children {
                removeChildrenFromNodes(grandchildren, nodes: &nodes)
            }
        }
    }

    private func updateNewChildCommentsButton(for parent: RenderableComment) {
        let parentId = parent.comment.id
        var updatedNodes = visibleNodes

        if let existingButton = newChildCommentsButtons[parentId],
           let buttonIndex = updatedNodes.firstIndex(where: { $0.id == existingButton.id }) {
            let newButton = RenderableButton(
                buttonType: .newChildComments,
                commentCount: parent.getNewChildCommentsCount(),
                parentId: parentId
            )
            newChildCommentsButtons[parentId] = newButton
            updatedNodes[buttonIndex] = newButton
        } else {
            let lastChildIndex = findLastChildIndex(parent, in: updatedNodes)
            let newButton = RenderableButton(
                buttonType: .newChildComments,
                commentCount: parent.getNewChildCommentsCount(),
                parentId: parentId
            )
            newChildCommentsButtons[parentId] = newButton
            updatedNodes.insert(newButton, at: lastChildIndex + 1)
        }

        visibleNodes = updatedNodes
    }

    private func requestPresenceForComment(_ renderable: RenderableComment) {
        let userId = renderable.comment.userId ?? renderable.comment.anonUserId
        if let userId = userId {
            onPresenceNeeded?([userId])
        }
    }
}
