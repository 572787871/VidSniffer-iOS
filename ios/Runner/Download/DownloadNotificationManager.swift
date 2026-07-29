import Foundation
import UserNotifications

struct DownloadNotificationManager {
  func requestAuthorizationIfNeeded() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      return true
    case .notDetermined:
      return (try? await center.requestAuthorization(
        options: [.alert, .sound]
      )) ?? false
    case .denied:
      return false
    @unknown default:
      return false
    }
  }

  func notifyCompletion(of task: DownloadTaskModel) async {
    guard await requestAuthorizationIfNeeded() else { return }
    let content = UNMutableNotificationContent()
    content.title = "下载完成"
    content.body = task.filename
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "download-\(task.id.uuidString)",
      content: content,
      trigger: nil
    )
    try? await UNUserNotificationCenter.current().add(request)
  }
}
