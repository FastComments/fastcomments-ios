import SwiftUI
import FastCommentsUI
import FastCommentsSwift
#if canImport(UIKit)
import UIKit
#endif

struct BenchmarkView: View {
    var autoRun: Bool = false

    @StateObject private var sdk = FastCommentsSDK(
        config: FastCommentsWidgetConfig(tenantId: "benchmark", urlId: "benchmark")
    )
    #if canImport(UIKit)
    @StateObject private var fpsMonitor = FPSMonitor()
    #endif

    @State private var generationTimeMs: Double = 0
    @State private var insertionTimeMs: Double = 0
    @State private var memoryBeforeMB: Double = 0
    @State private var memoryAfterMB: Double = 0
    @State private var commentCount: Int = 0
    @State private var isRunning = false
    @State private var hasRun = false

    var body: some View {
        VStack(spacing: 0) {
            statsPanel
            Divider()
            ZStack(alignment: .topTrailing) {
                LiveChatView(sdk: sdk)
                #if canImport(UIKit)
                fpsOverlay
                #endif
            }
        }
        .navigationTitle("100k Benchmark")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isRunning {
                    ProgressView()
                } else {
                    Button(hasRun ? "Reset & Run" : "Run") {
                        Task { await runBenchmark() }
                    }
                }
            }
        }
        #if canImport(UIKit)
        .onAppear { fpsMonitor.start() }
        .onDisappear {
            fpsMonitor.stop()
            sdk.commentsTree.build(comments: [])
        }
        #endif
        .task {
            if autoRun && !hasRun {
                await runBenchmark()
            }
        }
    }

    // MARK: - Stats Panel

    private var statsPanel: some View {
        VStack(spacing: 6) {
            if hasRun {
                HStack(spacing: 16) {
                    statItem("Comments", "\(commentCount.formatted())")
                    statItem("Gen", "\(String(format: "%.0f", generationTimeMs)) ms")
                    statItem("Insert", "\(String(format: "%.0f", insertionTimeMs)) ms")
                }
                HStack(spacing: 16) {
                    statItem("Mem Before", "\(String(format: "%.1f", memoryBeforeMB)) MB")
                    statItem("Mem After", "\(String(format: "%.1f", memoryAfterMB)) MB")
                    statItem("Delta", "+\(String(format: "%.1f", memoryAfterMB - memoryBeforeMB)) MB")
                }
                #if canImport(UIKit)
                HStack(spacing: 16) {
                    statItem("FPS", String(format: "%.0f", fpsMonitor.currentFPS))
                    statItem("Min", String(format: "%.0f", fpsMonitor.minFPS == .infinity ? 0 : fpsMonitor.minFPS))
                    statItem("Avg", String(format: "%.0f", fpsMonitor.averageFPS))
                    statItem("Drops", "\(fpsMonitor.droppedFrameCount)")
                }
                #endif
            } else {
                Text("Tap Run to load 100,000 comments")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private func statItem(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.monospacedDigit().bold())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - FPS Overlay

    #if canImport(UIKit)
    private var fpsOverlay: some View {
        Text("\(Int(fpsMonitor.currentFPS)) fps")
            .font(.caption.monospacedDigit().bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(fpsColor.opacity(0.85))
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(8)
    }

    private var fpsColor: Color {
        if fpsMonitor.currentFPS >= 55 { return .green }
        if fpsMonitor.currentFPS >= 30 { return .yellow }
        return .red
    }
    #endif

    // MARK: - Benchmark

    private func runBenchmark() async {
        if hasRun {
            // Reset
            sdk.commentsTree.build(comments: [])
            commentCount = 0
            generationTimeMs = 0
            insertionTimeMs = 0
            memoryBeforeMB = 0
            memoryAfterMB = 0
            #if canImport(UIKit)
            fpsMonitor.stop()
            fpsMonitor.start()
            #endif
            // Small delay so the UI clears before re-populating
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        isRunning = true
        defer {
            isRunning = false
            hasRun = true
        }

        let memBefore = getMemoryUsageMB()
        memoryBeforeMB = memBefore
        print("[Benchmark] Memory before: \(String(format: "%.1f", memBefore)) MB")

        // Generate comments
        let genStart = CFAbsoluteTimeGetCurrent()
        let comments = generateComments(count: 100_000)
        let genEnd = CFAbsoluteTimeGetCurrent()
        let genMs = (genEnd - genStart) * 1000
        generationTimeMs = genMs
        print("[Benchmark] Generated \(comments.count) comments in \(String(format: "%.1f", genMs)) ms")

        // Insert via build()
        let insertStart = CFAbsoluteTimeGetCurrent()
        sdk.commentsTree.build(comments: comments)
        let insertEnd = CFAbsoluteTimeGetCurrent()
        let insertMs = (insertEnd - insertStart) * 1000
        insertionTimeMs = insertMs
        commentCount = comments.count
        print("[Benchmark] Inserted \(comments.count) comments via build() in \(String(format: "%.1f", insertMs)) ms")

        let memAfter = getMemoryUsageMB()
        memoryAfterMB = memAfter
        print("[Benchmark] Memory after: \(String(format: "%.1f", memAfter)) MB (delta: +\(String(format: "%.1f", memAfter - memBefore)) MB)")

        print("[Benchmark] Tree stats — visibleNodes: \(sdk.commentsTree.visibleSize()), allComments: \(sdk.commentsTree.totalSize())")

        // Let the first frame render, then run a scroll stress test
        try? await Task.sleep(nanoseconds: 500_000_000)
        await runScrollTest()
    }

    #if canImport(UIKit)
    /// Programmatically scroll the content to stress-test LazyVStack rendering.
    private func runScrollTest() async {
        print("[Benchmark] Starting scroll stress test...")

        guard let scrollView = findUIScrollView() else {
            print("[Benchmark] Could not find UIScrollView for scroll test")
            return
        }

        let contentHeight = scrollView.contentSize.height
        let viewHeight = scrollView.bounds.height
        guard contentHeight > viewHeight else {
            print("[Benchmark] Content too small to scroll")
            return
        }

        // Reset FPS tracking for the scroll portion
        fpsMonitor.stop()
        fpsMonitor.start()

        let steps = 20
        let stepSize = (contentHeight - viewHeight) / CGFloat(steps)

        // Scroll down in steps
        for i in 1...steps {
            let y = min(stepSize * CGFloat(i), contentHeight - viewHeight)
            scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            // Allow a few frames to render at each position
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        // Scroll back up
        for i in stride(from: steps - 1, through: 0, by: -1) {
            let y = stepSize * CGFloat(i)
            scrollView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        print("[Benchmark] Scroll test complete — FPS min: \(String(format: "%.1f", fpsMonitor.minFPS == .infinity ? 0 : fpsMonitor.minFPS)), avg: \(String(format: "%.1f", fpsMonitor.averageFPS)), max: \(String(format: "%.1f", fpsMonitor.maxFPS)), dropped: \(fpsMonitor.droppedFrameCount)")
    }

    /// Walk the view hierarchy to find the UIScrollView backing our SwiftUI ScrollView.
    private func findUIScrollView() -> UIScrollView? {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return nil }
        return findScrollView(in: window)
    }

    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let sv = view as? UIScrollView { return sv }
        for sub in view.subviews {
            if let found = findScrollView(in: sub) { return found }
        }
        return nil
    }
    #else
    private func runScrollTest() async {
        print("[Benchmark] Scroll test not available on this platform")
    }
    #endif

    // MARK: - Comment Generation

    private func generateComments(count: Int) -> [PublicComment] {
        let names = ["Alice", "Bob", "Charlie", "Dana", "Eve", "Frank", "Grace", "Hank"]
        let messages = [
            "<p>Hello everyone!</p>",
            "<p>Great point.</p>",
            "<p>I agree with this.</p>",
            "<p>Interesting take.</p>",
            "<p>Thanks for sharing.</p>",
            "<p>Nice one!</p>",
            "<p>Well said.</p>",
            "<p>Indeed, that makes sense.</p>",
        ]

        let baseDate = Date().addingTimeInterval(-3 * 24 * 3600) // 3 days ago
        var comments: [PublicComment] = []
        comments.reserveCapacity(count)

        for i in 0..<count {
            let comment = PublicComment(
                id: "bench-\(i)",
                commenterName: names[i % names.count],
                commentHTML: messages[i % messages.count],
                date: baseDate.addingTimeInterval(Double(i) * 2.6), // ~2.6s apart = 3 days over 100k
                verified: true
            )
            comments.append(comment)
        }

        return comments
    }

    // MARK: - Memory

    private func getMemoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / (1024 * 1024) : 0
    }
}
