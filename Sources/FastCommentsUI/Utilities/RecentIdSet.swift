/// Ids of our own writes, so their live echo is skipped. An echo arrives within seconds, and ones that never come
/// (live updates off, a dropped event) would otherwise pile up for the SDK's lifetime, so only the most recent are kept.
struct RecentIdSet {
    private let capacity: Int
    private var ids: Set<String> = []
    private var insertionOrder: [String] = []

    init(capacity: Int = 200) {
        self.capacity = capacity
    }

    var count: Int { ids.count }

    func contains(_ id: String) -> Bool {
        ids.contains(id)
    }

    mutating func insert(_ id: String) {
        guard ids.insert(id).inserted else { return }
        insertionOrder.append(id)
        if insertionOrder.count > capacity {
            ids.remove(insertionOrder.removeFirst())
        }
    }

    /// Returns whether the id was present.
    @discardableResult
    mutating func remove(_ id: String) -> Bool {
        guard ids.remove(id) != nil else { return false }
        insertionOrder.removeAll { $0 == id }
        return true
    }
}
