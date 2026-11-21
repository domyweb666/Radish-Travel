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
    }

    private func save() {
        guard ready else { return }
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(s)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            show("這一步沒有存成功，手機的空間可能滿了。", false)
        }
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
    func act(undoable: Bool = false, _ change: (inout AppState) -> String?) {
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
        withAnimation(Motion.change) {
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
        }
    }
}
