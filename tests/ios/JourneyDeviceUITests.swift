import XCTest
import Darwin

/// Device smoke coverage. Gameplay that changes farm assets belongs in an
/// isolated QA account; this suite only opens the app and restores foreground.
final class JourneyDeviceUITests: XCTestCase {
    private let app = XCUIApplication(bundleIdentifier: "app.gensen.maps")

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testColdLaunchAndForegroundRecovery() {
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(5)
        XCTAssertEqual(app.state, .runningForeground)
        capture("01-cold-launch")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground)
        capture("02-foreground-restored")
    }

    /// Run once on the fresh QA installation after reviewing the city-picker
    /// screenshot. It selects a city locally and browses the map; it never
    /// confirms farm creation, relocation, purchases, or rewards.
    func testCityMapEntryAndGestures() {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        sleep(1)
        capture("03-before-city-selection")

        // Los Angeles button in the observed iPhone 14 Pro portrait layout.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)).tap()
        sleep(12)
        XCTAssertEqual(app.state, .runningForeground)
        capture("04-city-map-entry")
        XCTAssertTrue(app.buttons["About this map"].exists,
                      "The native map view did not appear after choosing a city")

        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.40))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.38, dy: 0.44))
        start.press(forDuration: 0.1, thenDragTo: end)
        sleep(2)
        capture("05-map-after-drag")

        app.pinch(withScale: 1.4, velocity: 0.5)
        sleep(2)
        XCTAssertEqual(app.state, .runningForeground)
        capture("06-map-after-pinch")
    }

    /// Players who already own a farm skip city selection: a cold launch must
    /// reach the native map directly without any city tap. Opens the farm tab
    /// and returns; it never plants, relocates, purchases, or claims rewards.
    func testFarmOwnerColdLaunchLandsOnMap() {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(14)
        capture("owner-01-cold-launch")
        XCTAssertTrue(app.buttons["About this map"].exists,
                      "A farm owner's cold launch did not reach the native map")

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        sleep(3)
        capture("owner-02-foreground-restored")

        // Bottom tab bar Farm entry, then the farm header back button.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.945)).tap()
        sleep(10)
        capture("owner-03-farm")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.09)).tap()
        sleep(5)
        XCTAssertEqual(app.state, .runningForeground)
        capture("owner-04-back-to-map")
    }

    /// Read-only diagnostic for the user's TestFlight invitation issue.
    /// This is separate from Journey gameplay acceptance.
    func testInspectTestFlightInbox() {
        let testFlight = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
        testFlight.activate()
        XCTAssertTrue(testFlight.wait(for: .runningForeground, timeout: 15))
        sleep(4)
        capture("testflight-inbox", application: testFlight)
    }

    /// Preserve the currently displayed app state while recording the reported
    /// map failure. Do not choose a city or submit any farm action here.
    func testInspectJourneyCurrentScreen() {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        sleep(1)
        capture("journey-current-screen")
        sleep(8)
        capture("journey-current-screen-after-wait")
    }

    /// Compare city selection immediately after launch with a delayed entry.
    /// Both cases select the already chosen city and never generate a farm.
    func testCityMapStartupTiming() {
        for delay in [0, 4] {
            app.terminate()
            app.launch()
            if delay > 0 { sleep(UInt32(delay)) }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)).tap()
            sleep(8)
            XCTAssertEqual(app.state, .runningForeground)
            capture("map-startup-delay-\(delay)")
        }
    }

    /// A transient bind failure must not leave the native map permanently
    /// unavailable. This test targets the separate QA app with networking
    /// redirected away from the production game service.
    func testNativeMapRecoversAfterListenerFailure() {
        let qaApp = XCUIApplication(bundleIdentifier: "app.gensen.maps.mapqa")
        app.terminate()
        qaApp.terminate()
        var blocker = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        XCTAssertGreaterThanOrEqual(blocker, 0)
        defer { if blocker >= 0 { Darwin.close(blocker) } }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(46464).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(blocker, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        XCTAssertEqual(bound, 0, "Cannot reserve the QA loopback port: errno \(errno)")

        qaApp.launch()
        XCTAssertTrue(qaApp.wait(for: .runningForeground, timeout: 15))
        sleep(3)
        allowQAFirstRunWiFiIfShown()
        qaApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)).tap()
        sleep(3)
        capture("listener-port-held", application: qaApp)
        XCTAssertFalse(qaApp.buttons["About this map"].exists)

        Darwin.close(blocker)
        blocker = -1
        let deadline = Date().addingTimeInterval(18)
        while Date() < deadline && !qaApp.buttons["About this map"].exists {
            allowQAFirstRunWiFiIfShown()
            Thread.sleep(forTimeInterval: 0.25)
        }
        allowQAFirstRunWiFiIfShown()
        sleep(3)
        capture("listener-port-released", application: qaApp)
        XCTAssertTrue(qaApp.buttons["About this map"].exists,
                      "Map did not recover after the transient listener failure")
    }

    private func allowQAFirstRunWiFiIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let wifiOnly = springboard.buttons["仅限无线局域网"]
        if wifiOnly.exists { wifiOnly.tap() }
    }

    func testQAMapReentryForegroundAndGestures() {
        let qaApp = XCUIApplication(bundleIdentifier: "app.gensen.maps.mapqa")
        qaApp.activate()
        XCTAssertTrue(qaApp.wait(for: .runningForeground, timeout: 15))
        XCTAssertTrue(qaApp.buttons["About this map"].waitForExistence(timeout: 10))
        qaApp.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.90)).tap()
        sleep(1)
        capture("qa-returned-to-city-picker", application: qaApp)
        qaApp.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.475)).tap()
        sleep(8)
        XCTAssertTrue(qaApp.buttons["About this map"].exists)
        capture("qa-shanghai-map", application: qaApp)

        XCUIDevice.shared.press(.home)
        XCTAssertTrue(qaApp.wait(for: .runningBackground, timeout: 10))
        qaApp.activate()
        XCTAssertTrue(qaApp.wait(for: .runningForeground, timeout: 10))
        sleep(2)
        XCTAssertTrue(qaApp.buttons["About this map"].exists)
        capture("qa-map-foreground-restored", application: qaApp)

        let start = qaApp.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.40))
        let end = qaApp.coordinate(withNormalizedOffset: CGVector(dx: 0.42, dy: 0.44))
        start.press(forDuration: 0.1, thenDragTo: end)
        qaApp.pinch(withScale: 1.3, velocity: 0.5)
        sleep(2)
        XCTAssertTrue(qaApp.buttons["About this map"].exists)
        capture("qa-map-after-gestures", application: qaApp)
    }

    /// The TestFlight build this delivery expects. Update per upload; the tests
    /// refuse to install anything else that TestFlight happens to offer.
    private let expectedTestFlightVersion = "0.16.42"
    private let expectedTestFlightBuild = "Build 1"

    private func openTestFlightDetails(fresh: Bool = true) -> XCUIApplication {
        let tf = XCUIApplication(bundleIdentifier: "com.apple.TestFlight")
        // A running TestFlight can keep a stale detail page (an older build)
        // while its list already shows the new one; start it fresh.
        if fresh {
            tf.terminate()
            tf.launch()
            sleep(4)
        } else {
            tf.activate()
        }
        XCTAssertTrue(tf.wait(for: .runningForeground, timeout: 15))
        let details = tf.scrollViews["AppDetails"]
        if !fresh { return tf }
        if !details.exists {
            // TestFlight opened on its app list: open the Gensen detail page.
            let row = tf.staticTexts["Gensen"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 10))
            row.tap()
            XCTAssertTrue(details.waitForExistence(timeout: 10))
        }
        details.swipeDown()
        details.swipeDown()
        return tf
    }

    private func assertExpectedTestFlightBuild(_ tf: XCUIApplication) {
        let version = tf.staticTexts["TestFlight.appDetails.shortVersion"].firstMatch
        XCTAssertTrue(version.waitForExistence(timeout: 10))
        capture("testflight-details", application: tf)
        // The label spaces out the digits ("版本:0 . 16 . 42 Build 1").
        let label = version.label.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(label.contains(expectedTestFlightVersion)
                      && label.hasSuffix(expectedTestFlightBuild.replacingOccurrences(of: " ", with: "")),
                      "TestFlight offers \(version.label), not the expected build")
        XCTAssertEqual(tf.staticTexts["TestFlight.appDetails.title"].label, "Gensen")
    }

    /// Install only the expected Gensen build and wait for TestFlight's Open.
    func testInstallExpectedTestFlightBuild() {
        let tf = openTestFlightDetails()
        assertExpectedTestFlightBuild(tf)
        capture("testflight-before-install", application: tf)
        let install = tf.buttons["TestFlight.offerButton.install"]
        XCTAssertTrue(install.exists && install.isHittable)
        install.tap()
        sleep(3)
        capture("testflight-after-install-request", application: tf)
        let system = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if tf.alerts.count > 0 || system.alerts.count > 0 {
            capture("testflight-install-alert", application: system)
            return
        }
        let opened = tf.buttons["打开"].firstMatch.waitForExistence(timeout: 120)
        capture("testflight-install-finished", application: tf)
        XCTAssertTrue(opened, "TestFlight has not confirmed installation with Open")
    }

    /// Confirm TestFlight's "already installed" replacement for the expected build.
    func testConfirmExpectedTestFlightReplacement() {
        // Keep the pending "already installed" alert: do not restart TestFlight.
        let tf = openTestFlightDetails(fresh: false)
        assertExpectedTestFlightBuild(tf)
        let alert = tf.alerts["此 App 已经安装。"]
        XCTAssertTrue(alert.exists)
        alert.buttons["安装"].tap()
        let opened = tf.buttons["打开"].firstMatch.waitForExistence(timeout: 120)
        capture("testflight-installed", application: tf)
        XCTAssertTrue(opened, "TestFlight has not confirmed installation with Open")
    }

    private func capture(_ name: String, application: XCUIApplication? = nil) {
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let hierarchy = XCTAttachment(string: (application ?? app).debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
