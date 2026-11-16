import SwiftUI
import FastCommentsSwift
import os.log

private let pollVotersLog = Logger(subsystem: "com.fastcomments", category: "PollVoters")

/// Loads "who voted" pages for `PollVotersSheet`.
@MainActor
final class PollVotersModel: ObservableObject {
    @Published private(set) var voters: [PollVoterEntry] = []
    @Published private(set) var total = 0
    @Published private(set) var isLoading = false
    @Published private(set) var didFail = false

    private let sdk: FastCommentsSDK
    private let commentId: String
    private var search = ""
    private var nextPage = 0
    private var hasMore = false
    private var hasFinishedLoading = false
    // Every fetch claims an id so a slow earlier page cannot overwrite a newer search when it lands.
    private var requestId = 0

    init(sdk: FastCommentsSDK, commentId: String) {
        self.sdk = sdk
        self.commentId = commentId
    }

    /// True once a request has finished with nobody to list, so the empty state doesn't flash while loading.
    var isEmpty: Bool { voters.isEmpty && hasFinishedLoading && !isLoading && !didFail }

    /// The search scans joined names server side, so it runs when submitted rather than on every keystroke.
    func applySearch(_ newSearch: String) async {
        let trimmed = newSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != search else { return }
        search = trimmed
        await reload()
    }

    func reload() async {
        nextPage = 0
        hasMore = false
        voters = []
        await fetchNextPage()
    }

    /// Pulls the next page once the last loaded row scrolls into view.
    func loadMoreIfNeeded(afterRowAt index: Int) async {
        guard index == voters.count - 1, hasMore, !isLoading else { return }
        await fetchNextPage()
    }

    // The page only advances once it arrives, so a failed fetch retries the same page.
    private func fetchNextPage() async {
        requestId += 1
        let id = requestId
        isLoading = true
        didFail = false
        do {
            let response = try await sdk.getPollVoters(
                commentId: commentId, page: nextPage, search: search.isEmpty ? nil : search)
            guard id == requestId else { return }
            voters += response.voters
            total = response.total
            hasMore = response.hasMore
            nextPage += 1
        } catch {
            guard id == requestId else { return }
            pollVotersLog.error("Loading poll voters failed: \(error.localizedDescription, privacy: .public)")
            didFail = true
        }
        isLoading = false
        hasFinishedLoading = true
    }
}

/// "Who voted" for a poll whose privacy names its voters. Mirrors the web widget's voters modal.
struct PollVotersSheet: View {
    @StateObject private var model: PollVotersModel
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss

    init(sdk: FastCommentsSDK, commentId: String) {
        _model = StateObject(wrappedValue: PollVotersModel(sdk: sdk, commentId: commentId))
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(model.voters.enumerated()), id: \.offset) { index, voter in
                    row(for: voter)
                        .task { await model.loadMoreIfNeeded(afterRowAt: index) }
                }

                statusRow
            }
            .listStyle(.plain)
            .accessibilityIdentifier("poll-voters-list")
            .navigationTitle(NSLocalizedString("poll_voters_title", bundle: .module, comment: ""))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: NSLocalizedString("poll_voters_search_placeholder", bundle: .module, comment: "")
                )
            #else
                .searchable(
                    text: $searchText,
                    prompt: NSLocalizedString("poll_voters_search_placeholder", bundle: .module, comment: "")
                )
            #endif
            .onSubmit(of: .search) {
                Task { await model.applySearch(searchText) }
            }
            .onChange(of: searchText) { newText in
                // Clearing the field is the one change that shouldn't wait for the search key.
                if newText.isEmpty {
                    Task { await model.applySearch("") }
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("poll_voters_close", bundle: .module, comment: "")) {
                        dismiss()
                    }
                    .accessibilityIdentifier("poll-voters-close")
                }
                if model.total > 0 {
                    ToolbarItem(placement: .primaryAction) {
                        Text(
                            String.localizedStringWithFormat(
                                NSLocalizedString("poll_voters_count_%lld", bundle: .module, comment: ""),
                                model.total)
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("poll-voters-count")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { await model.reload() }
    }

    private func row(for voter: PollVoterEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(voter.name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Option labels are stored entity-escaped, like on the poll card.
            Text(PollRules.plainText(fromEscaped: voter.optionLabel))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var statusRow: some View {
        if model.didFail {
            Button {
                Task { await model.reload() }
            } label: {
                statusText(NSLocalizedString("poll_voters_failed", bundle: .module, comment: ""))
            }
            .buttonStyle(.plain)
            .listRowSeparator(.hidden)
            .accessibilityIdentifier("poll-voters-failed")
        } else if model.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .listRowSeparator(.hidden)
                .accessibilityLabel(NSLocalizedString("poll_voters_loading", bundle: .module, comment: ""))
        } else if model.isEmpty {
            statusText(NSLocalizedString("poll_voters_none", bundle: .module, comment: ""))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("poll-voters-none")
        }
    }

    private func statusText(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}
