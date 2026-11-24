// 跟系統打交道的小東西：本機通知、跳到外部地圖、分享檔案。
// 對應 mobile/src/io/reminders.ts、mobile/src/sheets/links.ts。
import SwiftUI
import UIKit
import UserNotifications

// MARK: - 本機通知
// 只用來提醒「要先訂的還沒訂」。不連網路、不送任何資料出去。
// 權限只在使用者按了「出發前提醒我」之後才問。

enum AskResult {
    case granted, denied
}

/// app 開著的時候通知也照樣顯示
final class NoticeDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NoticeDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }
}

/// 問可不可以發通知。已經允許就直接回 granted；之前拒絕過，系統不會再問，回 denied
func askReminders() async -> AskResult {
    let center = UNUserNotificationCenter.current()
    center.delegate = NoticeDelegate.shared
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
        return .granted
    case .denied:
        return .denied
    case .notDetermined:
        let granted: Bool = (try? await center.requestAuthorization(options: [.alert])) ?? false
        return granted ? .granted : .denied
    @unknown default:
        return .denied
    }
}

/// 重排通知排成一條隊：前一次做完才做下一次，而且只有最後一次的內容算數。
/// 不排隊的話，前一次的「加」可能落在後一次的「清空」之後，關掉提醒了還會響
@MainActor
private enum ReminderLine {
    static var latest: Int = 0
    static var tail: Task<Void, Never>?
}

/// 還是最後一次嗎。後面又來了一次，前面的就不用再排下去
@MainActor
private func isLatestReminders(_ turn: Int) -> Bool {
    return turn == ReminderLine.latest
}

/// 把排好的通知整批換成這一份。綁在主執行緒上，號碼才會照呼叫的順序拿
@MainActor
func syncReminders(_ list: [Reminder]) async {
    ReminderLine.latest += 1
    let turn: Int = ReminderLine.latest
    let before: Task<Void, Never>? = ReminderLine.tail
    let job: Task<Void, Never> = Task { @MainActor in
        await before?.value
        guard isLatestReminders(turn) else { return }
        await replaceReminders(list, turn)
    }
    ReminderLine.tail = job
    await job.value
}

/// 真的去換。這個 app 沒有別種通知，所以先全部取消再重排。早上九點提醒
private func replaceReminders(_ list: [Reminder], _ turn: Int) async {
    let center = UNUserNotificationCenter.current()
    center.delegate = NoticeDelegate.shared
    center.removeAllPendingNotificationRequests()
    guard !list.isEmpty else { return }
    let settings = await center.notificationSettings()
    guard settings.authorizationStatus == .authorized else { return }
    for item in list {
        guard let when: DateComponents = reminderTime(item.on) else { continue }
        let still: Bool = await isLatestReminders(turn)
        guard still else { return }
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
        let request = UNNotificationRequest(
            identifier: "remind-\(item.on)-\(item.title)", content: content, trigger: trigger)
        // 排不成不影響其他功能；「這趟」頁上的提醒條還在
        try? await center.add(request)
    }
}

// MARK: - 跳到外部地圖
// 韓國當地找路用 Naver 地圖；沒裝就開網頁版。

private func encodeQuery(_ text: String) -> String {
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.~")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
}

@MainActor
func openNaver(_ query: String) {
    let encoded = encodeQuery(query)
    let web = URL(string: "https://map.naver.com/p/search/\(encoded)")
    guard let app = URL(string: "nmap://search?query=\(encoded)&appname=org.domyweb.radish") else { return }
    UIApplication.shared.open(app, options: [:]) { opened in
        if !opened, let web {
            Task { @MainActor in
                UIApplication.shared.open(web)
            }
        }
    }
}

@MainActor
func openGoogle(_ query: String) {
    guard let url = URL(string: "https://www.google.com/maps/search/?api=1&query=\(encodeQuery(query))")
    else { return }
    UIApplication.shared.open(url)
}

@MainActor
func openApple(_ query: String) {
    guard let url = URL(string: "https://maps.apple.com/?q=\(encodeQuery(query))") else { return }
    UIApplication.shared.open(url)
}

// MARK: - 分享

/// 系統的分享選單。用法：`.sheet(item: $share) { ShareSheet(items: [$0.url]) }`
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 要分享的一個檔案或一段字。給 `.sheet(item:)` 用
struct ShareItem: Identifiable {
    let id = UUID()
    let items: [Any]
}
