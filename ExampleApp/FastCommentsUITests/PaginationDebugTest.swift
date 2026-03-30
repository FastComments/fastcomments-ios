import XCTest

/// Debug test that launches the ExampleApp with the default demo data
/// (same as CommentsExampleView) and exercises pagination.
final class PaginationDebugTest: XCTestCase {

    func testDemoPagination() {
        let app = XCUIApplication()
        app.launchArguments = ["-screenshot", "comments"]
        app.launch()

        // Wait for comments to load
        let scrollView = app.scrollViews.firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 15), "ScrollView should appear")

        // Log initial visible comments
        let initialComments = app.staticTexts.allElementsBoundByIndex.filter {
            !$0.label.isEmpty && $0.frame.height > 10
        }
        print("[DEBUG] Initial elements: \(initialComments.count)")
        for el in initialComments.prefix(10) {
            print("[DEBUG]   \(el.label.prefix(80))")
        }

        // Scroll to bottom to find pagination
        for i in 0..<10 {
            scrollView.swipeUp()
            let nextBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
            if nextBtn.exists {
                print("[DEBUG] Found Next button after \(i+1) swipes: \(nextBtn.label)")
                break
            }
        }

        let nextButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Next'")).firstMatch
        guard nextButton.exists else {
            print("[DEBUG] No Next button found — not enough comments for pagination")
            return
        }

        print("[DEBUG] Next button label: \(nextButton.label)")

        // Tap Next
        print("[DEBUG] Tapping Next...")
        nextButton.tap()
        sleep(3)

        // Log what's visible after tap
        let afterComments = app.staticTexts.allElementsBoundByIndex.filter {
            !$0.label.isEmpty && $0.frame.height > 10
        }
        print("[DEBUG] After Next tap, visible elements: \(afterComments.count)")
        for el in afterComments.prefix(10) {
            print("[DEBUG]   \(el.label.prefix(80))")
        }

        // Scroll down to see if new comments are below
        print("[DEBUG] Scrolling down after tap...")
        for i in 0..<5 {
            scrollView.swipeUp()
            let visible = app.staticTexts.allElementsBoundByIndex.filter {
                !$0.label.isEmpty && $0.frame.height > 10
            }
            print("[DEBUG] Swipe down \(i+1): \(visible.count) elements, first: \(visible.first?.label.prefix(60) ?? "none")")
        }

        // Scroll back to top
        print("[DEBUG] Scrolling back to top...")
        for _ in 0..<15 { scrollView.swipeDown() }

        let topComments = app.staticTexts.allElementsBoundByIndex.filter {
            !$0.label.isEmpty && $0.frame.height > 10
        }
        print("[DEBUG] At top after pagination: \(topComments.count) elements")
        for el in topComments.prefix(10) {
            print("[DEBUG]   \(el.label.prefix(80))")
        }
    }
}
