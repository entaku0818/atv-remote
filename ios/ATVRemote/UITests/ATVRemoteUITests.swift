import XCTest

final class ATVRemoteUITests: XCTestCase {
    func testStoreScreenshots() {
        let app = XCUIApplication()
        app.launchArguments += ["--store-screenshots"]
        app.launch()
        XCTAssertTrue(app.buttons["settings"].waitForExistence(timeout: 10))
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "01-home"
        home.lifetime = .keepAlways
        add(home)
        app.staticTexts["リビングのTV"].tap()
        XCTAssertTrue(app.buttons["決定"].waitForExistence(timeout: 5))
        let remote = XCTAttachment(screenshot: app.screenshot())
        remote.name = "02-remote"
        remote.lifetime = .keepAlways
        add(remote)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let help = app.buttons["接続できないとき"]
        if !help.isHittable { app.swipeUp() }
        XCTAssertTrue(help.waitForExistence(timeout: 5))
        help.tap()
        XCTAssertTrue(app.navigationBars["接続ガイド"].waitForExistence(timeout: 5))
        let guide = XCTAttachment(screenshot: app.screenshot())
        guide.name = "03-guide"
        guide.lifetime = .keepAlways
        add(guide)
    }

    func testSettingsAndPrivacyAreAvailableWithoutATV() {
        let app = XCUIApplication()
        app.launch()
        let settings = app.buttons["settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        XCTAssertTrue(app.buttons["プライバシーについて"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["購入を復元"].exists)
        XCTAssertFalse(app.buttons["買い切りで全機能を解除"].exists)
        app.buttons["プライバシーについて"].tap()
        XCTAssertTrue(app.staticTexts["収集するデータ"].waitForExistence(timeout: 5))
    }

    func testInvalidManualAddressDoesNotOfferConnection() {
        let app = XCUIApplication()
        app.launch()
        let input = app.textFields["manualIP"]
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("999.999.999.999")
        XCTAssertFalse(app.buttons["このIPアドレスに接続"].exists)
    }
}
