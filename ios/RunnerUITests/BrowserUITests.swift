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
    XCTAssertTrue(app.buttons["browser.tabCount"].exists)
    XCTAssertTrue(app.buttons["browser.more"].exists)
    XCTAssertTrue(app.buttons["browser.tabs"].exists)
  }

  func testOpenTabSwitcherAndCreateTab() {
    let tabCount = app.buttons["browser.tabCount"]
    XCTAssertTrue(tabCount.waitForExistence(timeout: 5))
    tabCount.tap()

    let navigationBar = app.navigationBars["标签页"]
    XCTAssertTrue(navigationBar.waitForExistence(timeout: 5))

    let newTab = navigationBar.buttons["tabs.new"]
    XCTAssertTrue(newTab.exists)
    newTab.tap()

    let menuItem = app.buttons["新建标签页"]
    XCTAssertTrue(menuItem.waitForExistence(timeout: 2))
    menuItem.tap()

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
