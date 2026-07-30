import UIKit

@MainActor
final class MainTabBarController: UITabBarController {
  override func viewDidLoad() {
    super.viewDidLoad()
    configureAppearance()

    let browser = BrowserViewController()
    browser.tabBarItem = UITabBarItem(
      title: "浏览器",
      image: UIImage(systemName: "globe"),
      selectedImage: UIImage(systemName: "globe")
    )

    let parser = navigation(
      root: SmartParseViewController(),
      title: "智能解析",
      image: "link.badge.plus"
    )
    let downloads = navigation(
      root: DownloadViewController(),
      title: "下载中",
      image: "arrow.down.circle"
    )
    let library = navigation(
      root: LibraryViewController(),
      title: "文件",
      image: "folder"
    )

    viewControllers = [browser, parser, downloads, library]
    tabBar.accessibilityIdentifier = "main.tabBar"
  }

  private func navigation(
    root: UIViewController,
    title: String,
    image: String
  ) -> UINavigationController {
    let controller = UINavigationController(rootViewController: root)
    controller.navigationBar.prefersLargeTitles = true
    controller.tabBarItem = UITabBarItem(
      title: title,
      image: UIImage(systemName: image),
      selectedImage: UIImage(systemName: image + ".fill")
        ?? UIImage(systemName: image)
    )
    return controller
  }

  private func configureAppearance() {
    let appearance = UITabBarAppearance()
    appearance.configureWithDefaultBackground()
    appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
    tabBar.standardAppearance = appearance
    if #available(iOS 15.0, *) {
      tabBar.scrollEdgeAppearance = appearance
    }
    tabBar.tintColor = .systemBlue
  }
}
