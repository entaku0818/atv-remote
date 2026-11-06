import XCTest

final class ATVRemoteUITests: XCTestCase {
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
