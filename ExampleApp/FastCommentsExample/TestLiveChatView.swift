import SwiftUI
import FastCommentsUI
import FastCommentsSwift

/// Live chat view for UI testing — driven entirely by launch arguments.
struct TestLiveChatView: View {
    let config: FastCommentsWidgetConfig
    @StateObject private var sdk: FastCommentsSDK

    init(config: FastCommentsWidgetConfig) {
        self.config = config
        let sdk = FastCommentsSDK(config: config)
        sdk.defaultSortDirection = .of
        sdk.showLiveRightAway = true
        _sdk = StateObject(wrappedValue: sdk)
    }

    var body: some View {
        LiveChatView(sdk: sdk)
            .task { try? await sdk.load() }
            .navigationTitle("Live Chat")
            .navigationBarTitleDisplayMode(.inline)
    }
}
