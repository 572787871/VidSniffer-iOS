import XCTest

final class BrowserUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments += ["-ui-testing"]
    app.launch()
  }

  func testBrowserChromeIsReachable() {
    XCTAssertTrue(
      app.textFields["browser.addressField"].waitForExistence(timeout: 5)
    )
    XCTAssertTrue(app.buttons["browser.videoDetect"].exists)
    XCTAssertTrue(app.buttons["browser.user"].exists)
    XCTAssertTrue(app.buttons["browser.more"].exists)
    XCTAssertTrue(app.buttons["browser.tabs"].exists)
    XCTAssertTrue(app.buttons["browser.back"].exists)
    XCTAssertTrue(app.buttons["browser.forward"].exists)
    XCTAssertEqual(app.tabBars.count, 0)
  }

  func testVideoDetectionIsIntegratedIntoBrowserChrome() {
    let detector = app.buttons["browser.videoDetect"]
    XCTAssertTrue(detector.waitForExistence(timeout: 5))
    detector.tap()
    XCTAssertTrue(app.alerts["暂未检测到视频"].waitForExistence(timeout: 2))
  }

  func testOpenTabSwitcherAndCreateTab() {
    let tabs = app.buttons["browser.tabs"]
    XCTAssertTrue(tabs.waitForExistence(timeout: 5))
    tabs.tap()

    let newTab = app.buttons["tabs.new"]
    XCTAssertTrue(newTab.waitForExistence(timeout: 5))
    newTab.tap()

    XCTAssertTrue(
      app.textFields["browser.addressField"].waitForExistence(timeout: 5)
    )
  }

  func testAddressEntryCanBeClearedWithoutNetwork() {
    let address = app.textFields["browser.addressField"]
    XCTAssertTrue(address.waitForExistence(timeout: 5))
    address.tap()
    address.typeText("example.com")

    let clear = app.buttons["browser.clearAddress"]
    XCTAssertTrue(clear.waitForExistence(timeout: 2))
    clear.tap()

    XCTAssertEqual(address.value as? String, "搜索或输入网址")
  }
}
