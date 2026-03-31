import SwiftUI

/// Navigation hub listing all example screens.
struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Quick Tour") {
                    NavigationLink {
                        ScreenshotTourView()
                            .navigationBarTitleDisplayMode(.inline)
                    } label: {
                        ExampleRow(
                            icon: "camera.viewfinder",
                            iconColor: .pink,
                            title: "Screenshot Tour",
                            description: "Cycle through all views for screenshots"
                        )
                    }
                }

                Section("Comments") {
                    NavigationLink {
                        CommentsExampleView()
                    } label: {
                        ExampleRow(
                            icon: "bubble.left.and.bubble.right",
                            iconColor: .blue,
                            title: "Threaded Comments",
                            description: "SSO, heart votes, detailed theme, and live updates"
                        )
                    }

                    NavigationLink {
                        LiveChatExampleView()
                    } label: {
                        ExampleRow(
                            icon: "message",
                            iconColor: .green,
                            title: "Live Chat",
                            description: "Real-time chat with auto-scroll and date separators"
                        )
                    }

                    NavigationLink {
                        ToolbarShowcaseView()
                    } label: {
                        ExampleRow(
                            icon: "paintbrush",
                            iconColor: .indigo,
                            title: "Custom Toolbar",
                            description: "Global and per-instance custom toolbar buttons"
                        )
                    }
                }

                Section("Feed") {
                    NavigationLink {
                        FeedExampleView()
                    } label: {
                        ExampleRow(
                            icon: "doc.richtext",
                            iconColor: .orange,
                            title: "Social Feed",
                            description: "SSO, post creation, comments, tag filtering, and error handling"
                        )
                    }

                    NavigationLink {
                        FeedCustomButtonsExampleView()
                    } label: {
                        ExampleRow(
                            icon: "plus.rectangle.on.rectangle",
                            iconColor: .purple,
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
                            icon: "person.crop.circle",
                            iconColor: .teal,
                            title: "Simple SSO",
                            description: "Client-side SSO for demos and testing"
                        )
                    }

                    NavigationLink {
                        SecureSSOExampleView()
                    } label: {
                        ExampleRow(
                            icon: "lock.shield",
                            iconColor: .red,
                            title: "Secure SSO",
                            description: "Production SSO with server-side token generation"
                        )
                    }
                }
            }
            .navigationTitle("FastComments")
        }
    }
}

struct ExampleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(iconColor.gradient)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }
}
