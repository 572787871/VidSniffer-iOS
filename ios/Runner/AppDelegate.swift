import UIKit

@main
@MainActor
final class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [
      UIApplication.LaunchOptionsKey: Any
    ]?
  ) -> Bool {
    let window = UIWindow(frame: UIScreen.main.bounds)
    window.rootViewController = BrowserViewController()
    window.makeKeyAndVisible()
    self.window = window
    return true
  }

  func applicationDidEnterBackground(_ application: UIApplication) {
    // BrowserSessionManager integration is completed in the session phase.
  }

  func applicationWillTerminate(_ application: UIApplication) {
    // Private tabs are destroyed by BrowserTabManager before persistence.
  }
}
