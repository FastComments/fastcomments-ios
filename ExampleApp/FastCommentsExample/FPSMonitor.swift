#if canImport(UIKit)
import UIKit

@MainActor
final class FPSMonitor: ObservableObject {
    @Published var currentFPS: Double = 0
    @Published var minFPS: Double = .infinity
    @Published var maxFPS: Double = 0
    @Published var droppedFrameCount: Int = 0

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount: Int = 0
    private var fpsSamples: [Double] = []

    func start() {
        stop()
        minFPS = .infinity
        maxFPS = 0
        droppedFrameCount = 0
        fpsSamples.removeAll()

        let link = CADisplayLink(target: DisplayLinkTarget { [weak self] link in
            self?.tick(link)
        }, selector: #selector(DisplayLinkTarget.handleDisplayLink(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        print("[Benchmark FPS] Monitor started")
    }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        lastTimestamp = 0
        frameCount = 0
        if !fpsSamples.isEmpty {
            let avg = fpsSamples.reduce(0, +) / Double(fpsSamples.count)
            print("[Benchmark FPS] Monitor stopped — avg: \(String(format: "%.1f", avg)), min: \(String(format: "%.1f", minFPS == .infinity ? 0 : minFPS)), max: \(String(format: "%.1f", maxFPS)), samples: \(fpsSamples.count), dropped: \(droppedFrameCount)")
        }
    }

    var averageFPS: Double {
        fpsSamples.isEmpty ? 0 : fpsSamples.reduce(0, +) / Double(fpsSamples.count)
    }

    private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            frameCount = 0
            return
        }

        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp

        if elapsed >= 1.0 {
            let fps = Double(frameCount) / elapsed
            currentFPS = fps
            fpsSamples.append(fps)

            if fps < minFPS { minFPS = fps }
            if fps > maxFPS { maxFPS = fps }

            // A "dropped frame" = FPS dipped below half of max display refresh (assume 60)
            if fps < 30 {
                droppedFrameCount += 1
            }

            print("[Benchmark FPS] \(String(format: "%.1f", fps)) fps (min: \(String(format: "%.1f", minFPS)), max: \(String(format: "%.1f", maxFPS)))")

            frameCount = 0
            lastTimestamp = link.timestamp
        }
    }
}

// CADisplayLink requires an @objc target; this avoids making FPSMonitor inherit NSObject.
private class DisplayLinkTarget: NSObject {
    let handler: (CADisplayLink) -> Void
    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }
    @objc func handleDisplayLink(_ link: CADisplayLink) {
        handler(link)
    }
}
#endif
