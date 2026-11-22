// 整個 App 的狀態：存在手機本機（Application Support 裡的一個 JSON 檔），沒網路也看得到全部。
// 會改到行程的動作都走 act(undoable: true)，每次留一份改之前的樣子，最多 20 步，可以復原。
// 對應 mobile/src/store.tsx。
// 檔尾的 extension 是跟 AI 講（talk）：手機先答、同意、沒網路、句數、送出、套上改動、確認卡、復原這次。
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
    /// 這一步的記號（跟 AI 講的那一輪才有），對話裡用它認「還是不是最後一步」
    let mark: String?
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
    /// 復原紀錄最上面那一步的記號。對話裡那一輪的記號跟它一樣，才能按「復原這次」
    private(set) var undoTop: String?
    /// 跟 AI 講的那一句現在怎樣：沒事、等同意、沒送出去（沒網路、句數用完）、送出中
    private(set) var talkStage: TalkStage = .idle
    /// 這趟還剩幾句可以問 AI。nil 是不限。
    /// ❓28 句數怎麼算還沒定、app 裡也還沒有計句數的程式，所以現在一律 nil：句數用完（線框 A20）的樣子做好了，但不會出現
    private(set) var talkLeft: Int? = nil
    /// 每個講的地方打到一半的字（每一天、每一站各一份），切分頁再回來還在。只放在記憶體，app 被關掉就沒了（❓39）
    var drafts: [TalkTarget: String] = [:]
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
        // 先開始盯網路，第一次要送給 AI 時才知道有沒有網路
        _ = NetWatch.shared
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
    /// mark 是這一步的記號（跟 AI 講的那一輪用），之後拿 undoTop 比對還是不是最後一步
    func act(undoable: Bool = false, animated: Bool = true, mark: String? = nil, _ change: (inout AppState) -> String?) {
        let prev = s
        var draft = s
        let message: String? = change(&draft)
        if undoable {
            undoStack.append(
                Snapshot(
                    trip: prev.trip, seeds: prev.seeds, pool: prev.pool, baskets: prev.baskets,
                    settingsDirty: prev.settingsDirty, learned: prev.settings.learned, mark: mark))
            if undoStack.count > AppStore.undoMax {
                undoStack.removeFirst()
            }
            canUndo = true
            undoTop = mark
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
        undoTop = undoStack.last?.mark
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
        undoTop = nil
        talkStage = .idle
        drafts = [:]
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

/* ---------- 跟 AI 講（片 2、片 3：線框 A1–A3、A14、A19–A21、New-Consent） ---------- */

/// 要 AI 的句子送不出去的原因
enum TalkHold: Equatable {
    /// 沒網路（線框 A19）
    case offline
    /// 這趟的 AI 句數用完了（線框 A20）
    case quota
}

enum TalkStage: Equatable {
    case idle
    /// 第一次要送給 AI：等「同意並送出」（S03，線框 New-Consent）
    case consent(text: String, target: TalkTarget)
    /// 要 AI 的這句沒有送出去，字留在講的那一列
    case held(TalkHold)
    /// 送出了，等回覆。同一時間只送一句
    case busy
}

/// 沒收到回覆時畫面上寫的錯誤代碼。不知道就是空字串
private func talkErrorCode(_ error: Error) -> String {
    if let e = error as? AskError { return e.description }
    if let e = error as? URLError { return "URLError \(e.code.rawValue)" }
    return ""
}

/// 一輪改動的記號：可能有兩個（直接改的、按了套用的），用空白隔開
private func talkMarks(_ m: ChatMsg) -> [String] {
    guard let raw = m.undo else { return [] }
    return raw.split(separator: " ").map { (x: Substring) -> String in String(x) }
}

extension AppStore {
    var talkBusy: Bool { talkStage == .busy }

    /// 要 AI 的句子現在送不送得出去。nil 是送得出去，或根本沒接 AI（全部本機指令，不用網路）
    var talkHold: TalkHold? {
        if !aiReady() { return nil }
        if !NetWatch.shared.online { return .offline }
        if let left = talkLeft, left <= 0 { return .quota }
        return nil
    }

    /// 講的地方在看第幾天。一站就是那一站排在第幾天
    func talkDayOf(_ target: TalkTarget) -> Int {
        switch target {
        case .day(let n):
            return n
        case .stop(let id):
            if let t = s.trip, let x = findItem(t, id) { return x.s.day }
            return 1
        }
    }

    private func talkStopId(_ target: TalkTarget) -> String? {
        if case .stop(let id) = target { return id }
        return nil
    }

    private var talkNow: TripNow? {
        return tripNow(phase.map { (p: Phase) -> ChatClock in chatClock(p) })
    }

    /// 這句手機自己答得出的話，回答案（❓15 暫定：手機先答）
    func talkPhone(_ text: String, target: TalkTarget) -> String? {
        return phoneAnswer(text, s, talkDayOf(target), talkStopId(target), talkNow)
    }

    /// 這句要不要送給 AI：手機答不出、又有接 AI。沒網路、句數用完時，這種句子送不出去
    func talkNeedsAI(_ text: String, target: TalkTarget) -> Bool {
        if !aiReady() { return false }
        return talkPhone(text, target: target) == nil
    }

    /// 講的那一列上面那排說法，照這趟走到哪換（02-流程 5-3）。
    /// 沒接 AI 的時候，換成本機指令聽得懂的
    func talkHints(_ target: TalkTarget) -> [String] {
        let remote: Bool = aiReady()
        switch target {
        case .stop:
            // 線框 A5
            return remote ? ["這站要注意什麼", "換一個類似的", "移到別天"] : ["這站要注意什麼", "不去這一站"]
        case .day(let n):
            if phase == Phase.done {
                // 線框 A9
                return ["這趟去了哪些地方", "下次再來有哪些"]
            }
            if case .trip(let today)? = phase, today == n {
                // 線框 A2
                let days: Int = s.trip?.days ?? n
                return ["接下來去哪", "附近還有什麼", n < days ? "明天要注意什麼" : "今天要注意什麼"]
            }
            // 線框 A1
            return remote ? ["這天太滿", "上午下午對調", "多排一間咖啡廳"] : ["這天太滿", "上午下午對調", "這趟想輕鬆一點"]
        }
    }

    /// 剛剛那一則：最後一句我說的，在對話裡第幾則。還沒講過是 nil
    var lastTalk: Int? {
        return s.chat.lastIndex { (m: ChatMsg) -> Bool in m.r == .me }
    }

    /// 這一輪的改動還是不是復原紀錄最上面那一步，是的話可以按「復原這次」
    func canUndoRound(_ m: ChatMsg) -> Bool {
        if m.undone == true { return false }
        guard let last = talkMarks(m).last else { return false }
        return last == undoTop
    }

    /// 送一句。手機答得出的當場答；要 AI 的先看網路、句數、有沒有同意過，才送出去。
    /// 回 true：收下了（已經答了、送出去了，或在等同意），呼叫的人可以 sheets.open(.reply)、清掉打的字。
    /// 回 false：沒送出去（沒網路、句數用完、正在等上一句），字留著，這趟不動
    @discardableResult
    func talk(_ text: String, target: TalkTarget) -> Bool {
        let msg: String = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty || talkBusy || s.trip == nil { return false }
        let day: Int = talkDayOf(target)
        let stop: String? = talkStopId(target)
        if let answer = talkPhone(msg, target: target) {
            talkStage = .idle
            let stamp: Double = Date().timeIntervalSince1970
            mutate { (d: inout AppState) -> Void in
                d.chat.append(ChatMsg(r: .me, t: msg, day: day, stop: stop))
                d.chat.append(ChatMsg(r: .ai, t: answer, day: day, stop: stop, local: true, at: stamp))
            }
            return true
        }
        let remote: Bool = aiReady()
        if remote {
            if let hold = talkHold {
                keepDraft(msg, target)
                talkStage = .held(hold)
                Haptic.notify(.error)
                return false
            }
            if !s.aiConsent {
                talkStage = .consent(text: msg, target: target)
                return true
            }
        }
        talkSend(msg, target, remote, retry: nil)
        return true
    }

    /// 第一次的說明按「同意並送出」
    func talkConsent() {
        guard case .consent(let text, let target) = talkStage else { return }
        mutate { (d: inout AppState) -> Void in
            d.aiConsent = true
        }
        talkStage = .idle
        if let hold = talkHold {
            keepDraft(text, target)
            talkStage = .held(hold)
            Haptic.notify(.error)
            return
        }
        talkSend(text, target, aiReady(), retry: nil)
    }

    /// 第一次的說明按「先不要」：什麼都不送，講的字放回那一列
    func talkDecline() {
        guard case .consent(let text, let target) = talkStage else { return }
        keepDraft(text, target)
        talkStage = .idle
    }

    /// 剛剛那一則收起來的時候：還在等同意的當作先不要；沒送出去的那句已經留在那一列了
    func talkDismiss() {
        switch talkStage {
        case .consent:
            talkDecline()
        case .held:
            talkStage = .idle
        case .idle, .busy:
            break
        }
    }

    /// 沒收到回覆的那句再送一次
    func retryTalk(_ index: Int) {
        guard index < s.chat.count, s.chat[index].r == .me, s.chat[index].failed != nil, !talkBusy else { return }
        let m: ChatMsg = s.chat[index]
        var target: TalkTarget = .day(m.day ?? 1)
        if let id = m.stop { target = .stop(id: id) }
        if let hold = talkHold {
            talkStage = .held(hold)
            Haptic.notify(.error)
            return
        }
        talkSend(m.t, target, aiReady(), retry: index)
    }

    /// 那一列是空的才把字放回去，不蓋掉他後來打的
    private func keepDraft(_ msg: String, _ target: TalkTarget) {
        let typed: String = drafts[target] ?? ""
        if typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            drafts[target] = msg
        }
    }

    /// 真的送出去：先記下我說的（再送一次就清掉沒收到的記號），再問 AI 或本機指令，回來再套上改動
    private func talkSend(_ msg: String, _ target: TalkTarget, _ remote: Bool, retry: Int?) {
        guard let trip = s.trip else { return }
        let day: Int = talkDayOf(target)
        let stop: String? = talkStopId(target)
        let settings: Settings = s.settings
        // 送給 AI 的前面幾句不含這一句（這一句在提示詞裡另外寫）
        var history: [ChatMsg] = s.chat
        if let i = retry { history = Array(s.chat.prefix(i)) }
        // 按下去那一刻的「現在」：AI 和套用改動都用同一個，免得送出到回來之間跨過時段
        let clock: ChatClock? = phase.map { (p: Phase) -> ChatClock in chatClock(p) }
        let focus: String = talkFocus(trip, stop == nil ? day : nil, stop)
        let heard: String = talkLocal(msg, trip, day, stop, stop == nil)
        talkStage = .busy
        mutate { (d: inout AppState) -> Void in
            // 還沒按的確認卡過期：行程接下來會變，那幾步不一定還對
            for i in d.chat.indices where d.chat[i].askOps != nil {
                d.chat[i].askOps = nil
                d.chat[i].asked = false
            }
            if let i = retry, i < d.chat.count {
                d.chat[i].failed = nil
            } else {
                d.chat.append(ChatMsg(r: .me, t: msg, day: day, stop: stop))
            }
        }
        let me: Int = retry ?? (s.chat.count - 1)
        Task { @MainActor in
            if remote {
                do {
                    let prompt: String = aiPrompt(msg, trip, settings, history, clock, focus)
                    let out: BrainOut = try await askRemote(prompt, AI_ENDPOINT)
                    self.talkFinish(out, local: false, me: me, said: msg, day: day, stop: stop, clock: clock)
                } catch {
                    // 沒回好、讀不懂：這趟不動，不退回本機指令（線框 A21）
                    self.talkFail(me: me, said: msg, error)
                }
            } else {
                let out: BrainOut = localBrain(heard, trip, tripNow(clock))
                self.talkFinish(out, local: true, me: me, said: msg, day: day, stop: stop, clock: clock)
            }
            self.talkStage = .idle
        }
    }

    /// 把回來的動作套到行程上，對話裡記下改了什麼、每一天差多少、哪幾步沒做成。有改到行程才留復原
    private func talkFinish(
        _ out: BrainOut, local: Bool, me: Int, said msg: String, day: Int, stop: String?, clock: ChatClock?
    ) {
        // 等回覆的時候這趟換了、對話清掉了：回來的不套
        guard me < s.chat.count, s.chat[me].r == .me, s.chat[me].t == msg, let current = s.trip else { return }
        let now: TripNow? = tripNow(clock)
        // 旅途中不整趟重排：去過的站會被洗掉
        let blockRegen: Bool = out.regen == true && now != nil
        let regen: Bool = out.regen == true && !blockRegen
        // 只有要確認的改動時，這一步還沒改到行程，不留復原
        let direct: Int = splitOps(current, out.ops).direct.count
        let willChange: Bool = regen || direct > 0
        let mark: String? = willChange ? UUID().uuidString : nil
        let stamp: Double = Date().timeIntervalSince1970
        act(undoable: willChange, mark: mark) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let before: Trip = trip
            var changes: [String] = []
            if regen {
                let own: (flight: Double, spend: [Spend]?, rate: Double?) = ownOf(trip)
                var fresh: Trip = generate(draftOf(trip), d.settings, true)
                fresh.flight = own.flight
                fresh.spend = own.spend
                fresh.rate = own.rate
                trip = fresh
                d.settingsDirty = false
                changes.append("整趟照現在的設定重排了")
            }
            var seeds: [Seed] = d.seeds
            // 權限表上要確認的先不改，放進確認卡
            let split: (direct: [Any], confirm: [[String: Any]]) = splitOps(trip, out.ops)
            let r: (changes: [String], notes: [String]) = applyOps(&trip, &seeds, split.direct, now)
            d.trip = trip
            d.seeds = seeds
            changes.append(contentsOf: r.changes)
            if !regen && !r.changes.isEmpty {
                changes.append(contentsOf: dayDeltas(before, trip, d.settings))
            }
            var said: ChatMsg = ChatMsg(r: .ai, t: out.reply, changes: changes, day: day, stop: stop)
            said.local = local ? true : nil
            said.at = stamp
            if regen || !r.changes.isEmpty { said.undo = mark }
            if !split.confirm.isEmpty {
                let after: Trip = trip
                said.ask = split.confirm.map { (o: [String: Any]) -> String in opLine(after, o) }
                said.askOps = packOps(split.confirm)
            }
            d.chat.append(said)
            if blockRegen {
                d.chat.append(ChatMsg(r: .sys, t: NO_REGEN_ON_TRIP))
            }
            let notes: [String] = r.notes + warnings(trip)
            for n in notes {
                d.chat.append(ChatMsg(r: .sys, t: n))
            }
            if hasAiPlace(out.ops) {
                d.chat.append(ChatMsg(r: .sys, t: "AI 自己加的地點還沒核對過，去之前查一下。"))
            }
            return nil
        }
    }

    /// 沒收到回覆：這趟不動，在我說的那句記下來，可以再送一次
    private func talkFail(me: Int, said msg: String, _ error: Error) {
        Haptic.notify(.error)
        let code: String = talkErrorCode(error)
        mutate { (d: inout AppState) -> Void in
            guard me < d.chat.count, d.chat[me].r == .me, d.chat[me].t == msg else { return }
            d.chat[me].failed = code
        }
    }

    /// 確認卡按「套用」：照權限表放行要確認的那幾步，可以復原
    func confirmAsk(_ index: Int) {
        guard index < s.chat.count, s.chat[index].askOps != nil, s.trip != nil else { return }
        let now: TripNow? = talkNow
        let mark: String = UUID().uuidString
        // 這一輪直接改的那一步還在最上面，套用的這一步就跟它算同一輪
        let together: Bool = canUndoRound(s.chat[index])
        act(undoable: true, mark: mark) { (d: inout AppState) -> String? in
            guard var trip = d.trip, index < d.chat.count, let raw = d.chat[index].askOps else { return nil }
            var seeds: [Seed] = d.seeds
            let r: (changes: [String], notes: [String]) = applyOps(&trip, &seeds, unpackOps(raw), now, true)
            let tweaked: Bool = trip.tweaks != d.trip?.tweaks
            d.trip = trip
            d.seeds = seeds
            d.chat[index].askOps = nil
            d.chat[index].asked = true
            if !r.changes.isEmpty {
                let old: String = d.chat[index].undo ?? ""
                d.chat[index].undo = together && !old.isEmpty ? old + " " + mark : mark
                d.chat[index].undone = nil
            }
            // 卡上已經寫「套用了」，有改到就不再多講一次
            if r.changes.isEmpty {
                d.chat.append(ChatMsg(r: .sys, t: "沒有改到東西。"))
            }
            for n in r.notes {
                d.chat.append(ChatMsg(r: .sys, t: n))
            }
            // 旅途中不整趟重排，就不提重排
            if tweaked && now == nil {
                d.chat.append(ChatMsg(r: .sys, t: "之後改行程會照這個排。想整趟照這個重排，說「重排」。"))
            }
            return nil
        }
    }

    /// 確認卡按「不要」：什麼都不改
    func skipAsk(_ index: Int) {
        mutate { (d: inout AppState) -> Void in
            guard index < d.chat.count, d.chat[index].askOps != nil else { return }
            d.chat[index].askOps = nil
            d.chat[index].asked = false
            d.chat.append(ChatMsg(r: .sys, t: "好，沒改。"))
        }
    }

    /// 「復原這次」：這一輪的改動還在最上面才退，退到這一輪之前
    func undoRound(_ index: Int) {
        guard index < s.chat.count, canUndoRound(s.chat[index]) else { return }
        let marks: [String] = talkMarks(s.chat[index])
        while let top = undoTop, marks.contains(top) {
            undo()
        }
        mutate { (d: inout AppState) -> Void in
            guard index < d.chat.count else { return }
            d.chat[index].undone = true
        }
    }
}
