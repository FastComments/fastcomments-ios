import SwiftUI

/// Navigation hub listing all example screens.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Comments") {
                    NavigationLink {
                        CommentsExampleView()
                    } label: {
                        ExampleRow(
                            title: "Threaded Comments",
                            description: "Basic comment widget with voting, replies, and live updates"
                        )
                    }

                    NavigationLink {
                        LiveChatExampleView()
                    } label: {
                        ExampleRow(
                            title: "Live Chat",
                            description: "Real-time chat with auto-scroll and date separators"
                        )
                    }

                    NavigationLink {
                        ToolbarShowcaseView()
                    } label: {
                        ExampleRow(
                            title: "Custom Toolbar",
                            description: "Add custom buttons to the comment input toolbar"
                        )
                    }
                }

                Section("Feed") {
                    NavigationLink {
                        FeedExampleView()
                    } label: {
                        ExampleRow(
                            title: "Social Feed",
                            description: "Post feed with reactions, media, and infinite scroll"
                        )
                    }

                    NavigationLink {
                        FeedCustomButtonsExampleView()
                    } label: {
                        ExampleRow(
                            title: "Feed Custom Buttons",
                            description: "Custom toolbar buttons on the post creation form"
                        )
                    }
                }

                Section("Authentication") {
                    NavigationLink {
                        SimpleSSOExampleView()
                    } label: {
                        ExampleRow(
                            title: "Simple SSO",
                            description: "Client-side SSO for demos and testing"
                        )
                    }

                    NavigationLink {
                        SecureSSOExampleView()
                    } label: {
                        ExampleRow(
                            title: "Secure SSO",
                            description: "Production SSO with server-side token generation"
                        )
                    }
                }
            }
            .navigationTitle("FastComments Examples")
        }
    }
}

struct ExampleRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(description)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
