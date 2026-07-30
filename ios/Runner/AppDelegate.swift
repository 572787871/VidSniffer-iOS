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
    // BrowserViewController persists normal tabs from the lifecycle notification.
  }

  func applicationWillTerminate(_ application: UIApplication) {
    // BrowserViewController excludes and destroys private tabs before persistence.
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    if identifier.hasSuffix(".hls-downloads") {
      HLSAssetDownloadService.shared.backgroundEventsCompletionHandler =
        completionHandler
    } else {
      BackgroundDownloadService.shared.backgroundEventsCompletionHandler =
        completionHandler
    }
  }
}
