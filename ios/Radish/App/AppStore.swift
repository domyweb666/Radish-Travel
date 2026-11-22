// 整個 App 的狀態：存在手機本機（Application Support 裡的一個 JSON 檔），沒網路也看得到全部。
// 會改到行程的動作都走 act(undoable: true)，每次留一份改之前的樣子，最多 20 步，可以復原。
// 對應 mobile/src/store.tsx。
import Foundation
import Observation
import SwiftUI

struct Notice: Equatable {
    let id: Int
    let text: String
    let canUndo: Bool
}

/// 復原要還原的那幾樣。learned 是設定裡「從行程學到的」：拿掉一站順便記的，要能跟著那一步一起復原
private struct Snapshot {
    let trip: Trip?
    let seeds: [Seed]
    let pool: [String]
    let baskets: [Basket]
    let settingsDirty: Bool
    let learned: [Learned]
}

@MainActor
@Observable
final class AppStore {
    nonisolated static let fileName = "radish-travel-v1.json"
    private static let undoMax = 20
    private static let noticeSeconds: Double = 8  // 提示停留時間，不是動畫

    private(set) var s = AppState()
    private(set) var ready = false
    private(set) var notice: Notice?
    private(set) var canUndo = false
    /// 今天（裝置當地），YYYY-MM-DD。app 回到前景時會更新
    private(set) var today: String = todayISO()

    @ObservationIgnored private var undoStack: [Snapshot] = []
    @ObservationIgnored private var noticeId = 0
    @ObservationIgnored private var noticeTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL
    /// 有改過、還沒寫進檔案
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// 寫檔排隊用：一次寫一份，照改的順序寫
    @ObservationIgnored private let writer = DispatchQueue(label: "org.domyweb.radish.save", qos: .utility)
    /// 上次排通知用的內容，沒變就不重排。nil 是還沒排過
    @ObservationIgnored private var reminderKey: String?
    /// 改完多久才寫檔，這段時間內再改就併成一次
    private static let saveDelay: Double = 0.3

    init(fileURL: URL = AppStore.defaultURL()) {
        self.fileURL = fileURL
    }

    nonisolated static func defaultURL() -> URL {
        let base: URL =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(fileName)
    }

    /// 這趟現在在哪個階段：出發前、旅途中、回來了。沒有行程就是 nil
    var phase: Phase? {
        guard let trip = s.trip else { return nil }
        return phaseOf(trip.start, trip.days, today, s.debugDay)
    }

    /// 開 app 時讀檔。檔案在但讀不出來時，把它改名留著（不蓋掉），從空白開始並說清楚
    func load() {
        guard !ready else { return }
        let manager = FileManager.default
        if manager.fileExists(atPath: fileURL.path) {
            let data: Data? = try? Data(contentsOf: fileURL)
            if let data, let state = AppState.hydrate(data) {
                s = state
            } else {
                let stamp = Int(Date().timeIntervalSince1970)
                let keep = fileURL.deletingLastPathComponent()
                    .appendingPathComponent("radish-travel-v1.unreadable-\(stamp).json")
                try? manager.moveItem(at: fileURL, to: keep)
                show("上次存的資料讀不出來，已經另外留一份沒有刪。現在先從空白開始。", false)
            }
        }
        ready = true
        syncReminderList()
    }

    /// 排一次存檔。連著改好幾下只寫最後那一份，寫檔在背景做，畫面不用等它。
    /// app 要離開前景時 RadishApp 會叫 flush(wait: true)，所以排著還沒寫的那一份不會掉
    private func save() {
        guard ready else { return }
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppStore.saveDelay))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// 現在就把還沒寫的那一份寫進檔案。wait 為 true 時等寫完才回來（app 要進背景時用）。
    /// 寫完順便把排好的通知換成新的
    func flush(wait: Bool = false) {
        saveTask?.cancel()
        saveTask = nil
        guard ready, dirty else { return }
        dirty = false
        let state: AppState = s
        let url: URL = fileURL
        let job: @Sendable () -> Void = { [weak self] in
            do {
                let dir = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(state)
                try data.write(to: url, options: .atomic)
            } catch {
                Task { @MainActor [weak self] in
                    self?.show("這一步沒有存成功，手機的空間可能滿了。", false)
                }
            }
        }
        if wait {
            writer.sync(execute: job)
        } else {
            writer.async(execute: job)
        }
        syncReminderList()
    }

    /// 行程、打勾、提醒開關有變，就把排好的通知整批換新。關掉提醒時是清空。內容跟上次一樣就不動
    private func syncReminderList() {
        guard ready else { return }
        let list: [Reminder] = s.remind ? remindersOf(s, today) : []
        let key: String = list.map { (item: Reminder) -> String in "\(item.on)|\(item.title)|\(item.body)" }
            .joined(separator: "/")
        if key == reminderKey { return }
        reminderKey = key
        Task { await syncReminders(list) }
    }

    private func show(_ text: String, _ undoable: Bool) {
        noticeTask?.cancel()
        noticeId += 1
        let id = noticeId
        withAnimation(Motion.transition) {
            notice = Notice(id: id, text: text, canUndo: undoable)
        }
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(AppStore.noticeSeconds))
            guard !Task.isCancelled else { return }
            self?.clearNotice(id)
        }
    }

    private func clearNotice(_ id: Int) {
        guard notice?.id == id else { return }
        withAnimation(Motion.transition) {
            notice = nil
        }
    }

    /// 改狀態。fn 直接改 draft；回傳的字串會顯示在提示條（回 nil 就不顯示）。
    /// undoable 為 true 時這一步可以復原。會改到行程的動作都要 undoable: true。
    func act(undoable: Bool = false, animated: Bool = true, _ change: (inout AppState) -> String?) {
        let prev = s
        var draft = s
        let message: String? = change(&draft)
        if undoable {
            undoStack.append(
                Snapshot(
                    trip: prev.trip, seeds: prev.seeds, pool: prev.pool, baskets: prev.baskets,
                    settingsDirty: prev.settingsDirty, learned: prev.settings.learned))
            if undoStack.count > AppStore.undoMax {
                undoStack.removeFirst()
            }
            canUndo = true
        }
        // 資料變了要看得出哪裡動了：列表增減、數字換值都用同一條曲線
        // animated 傳 false 的情況：同一下還要開全螢幕的東西（拔蘿蔔），兩個動畫撞在一起那張會開不出來
        if animated {
            withAnimation(Motion.change) {
                s = draft
            }
        } else {
            s = draft
        }
        save()
        if let message, !message.isEmpty {
            show(message, undoable)
        }
    }

    /// 跟 act 一樣，只是不顯示提示條
    func mutate(undoable: Bool = false, _ change: (inout AppState) -> Void) {
        act(undoable: undoable) { draft in
            change(&draft)
            return nil
        }
    }

    /// 改「我」裡的偏好。有行程時會記下「設定改過、還沒套到這趟」
    func setSettings(_ change: (inout Settings) -> Void) {
        mutate { draft in
            change(&draft.settings)
            draft.settings.tuned = true
            if draft.trip != nil {
                draft.settingsDirty = true
            }
        }
    }

    func undo() {
        guard let snap = undoStack.popLast() else { return }
        canUndo = !undoStack.isEmpty
        var next = s
        next.trip = snap.trip
        next.seeds = snap.seeds
        next.pool = snap.pool
        next.baskets = snap.baskets
        next.settingsDirty = snap.settingsDirty
        next.settings.learned = snap.learned
        withAnimation(Motion.change) {
            s = next
        }
        save()
        show("復原了上一步。", false)
    }

    /// 只顯示一句話，不改資料
    func say(_ text: String) {
        show(text, false)
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    /// 整包換掉（清除全部、匯入）。復原紀錄會清空
    func replaceAll(_ next: AppState) {
        undoStack = []
        canUndo = false
        s = next
        save()
    }

    /// app 回到前景時叫一次：跨過午夜之後「今天」要跟著變
    func refreshToday() {
        let now = todayISO()
        if now != today {
            today = now
            syncReminderList()
        }
    }
}
