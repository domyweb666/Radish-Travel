// 整個 App 的狀態：存在手機本機（Application Support 裡的一個 JSON 檔），沒網路也看得到全部。
// 會改到行程的動作都走 act(undoable: true)，每次留一份改之前的樣子，最多 20 步，可以復原。
// 換掉現在這趟的動作（切到別趟、開新的一趟、收起來、不要這一版）一定會留一步，規則在 TripActions.swift 的 applyUndo。
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

/// 一趟打到一半的字。換了一趟就收在這裡，換回來再拿出來
private struct TalkDrafts {
    var now: [TalkTarget: String] = [:]
    var later: [TalkTarget: [String]] = [:]
    /// 第 1 天那一列裡，從開一趟時寫的那句改出來、還沒講的字
    var wishLine: String?
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
    /// 每個講的地方打到一半的字（每一天、每一站各一份），切分頁再回來還在。只放在記憶體，app 被關掉就沒了（❓39）
    /// 每一趟各一份：換了一趟就換成那一趟的
    var drafts: [TalkTarget: String] = [:]
    /// 開一趟填到一半的。切分頁、去平常的我再回來都還在，開好了或整包換掉才清。只放在記憶體（❓39）
    var startDraft: StartDraft = StartDraft()
    /// 今天（裝置當地），YYYY-MM-DD。app 回到前景時會更新
    private(set) var today: String = todayISO()
    /// 平常的我裡有沒有填 Claude API 金鑰。金鑰本身在鑰匙圈和 CLAUDE_KEY，這裡只是讓畫面知道要重畫
    private(set) var claudeKeySet: Bool = !CLAUDE_KEY.isEmpty
    /// 有沒有連電腦的 Claude CLI（開發測試用）。網址在鑰匙圈和 BRIDGE_URL
    private(set) var bridgeSet: Bool = !BRIDGE_URL.isEmpty
    /// 要 AI 的句子現在會送去哪裡，沒接 AI 是 nil。判斷在 Chat.swift 的 aiRoute，這裡留一份讓畫面知道要重畫
    private(set) var aiDest: AIDest? = aiDestNow()

    @ObservationIgnored private var undoStack: [UndoSnap] = []
    /// 沒送出去、但那一列正在打別的：先放這裡，那一列空了再放回去
    @ObservationIgnored private var keptTalk: [TalkTarget: [String]] = [:]
    /// 第 1 天那一列裡，從開一趟時寫的那句改出來、還沒講的字（wishTyped）。沒有改就是 nil
    @ObservationIgnored private var wishLine: String?
    /// 第幾次送出。整包換掉也加一：之前送的那句回來時對不上，就不套、也不動現在的狀態
    @ObservationIgnored private var talkSeq: Int = 0
    /// 別趟打到一半的字，用 Trip.id 記
    @ObservationIgnored private var draftBox: [String: TalkDrafts] = [:]
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

    /// 接上 AI 了沒：有連電腦的 CLI、有填 Claude API 金鑰，或建置時設了後端網址。畫面讀這個才會在填金鑰後跟著變
    var aiOn: Bool {
        return aiDest != nil
    }

    /// 現在會送去的那個地方同意過了嗎。換到沒同意過的地方就是 false
    var aiAgreedHere: Bool {
        return aiAllowed(s, aiDest)
    }

    /// 這趟還剩幾句可以問 AI。nil 是不限（自己的金鑰、自己電腦的 CLI、沒接 AI）。規則在 Chat.swift 的 aiLeft
    var talkLeft: Int? {
        guard let trip = s.trip else { return nil }
        _ = aiDest
        return aiLeft(trip, firstTrip: s.baskets.isEmpty && s.shelf.isEmpty, metered: aiMetered())
    }

    /// AI 有回一句：那一趟的句數加一，沒給代號就是現在這趟。不留復原，復原行程也不退句數。
    /// 給代號（送出時的那一趟），等回覆的時候換了一趟也不會算錯
    func countAISentence(_ tripId: String? = nil) {
        let target: String? = tripId ?? s.trip?.id
        guard let id = target else { return }
        mutate { (d: inout AppState) -> Void in
            countAI(&d, id)
        }
    }

    /// 存或清掉 Claude API 金鑰（nil 或空字串是清掉）。存進鑰匙圈，不進存檔、不進備份。
    /// 沒存成功回 false：原本的不動，提示條講清楚，叫的人不要再說可以用了
    @discardableResult
    func setClaudeKey(_ key: String?) -> Bool {
        let clean: String = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            SecretStore.clear(.claudeKey)
            CLAUDE_KEY = ""
        } else {
            guard SecretStore.save(.claudeKey, clean) else {
                show("金鑰沒有存成功，等一下再試一次。", false)
                return false
            }
            CLAUDE_KEY = clean
        }
        claudeKeySet = !CLAUDE_KEY.isEmpty
        aiDest = aiDestNow()
        return true
    }

    /// 存或清掉連電腦 Claude CLI 的網址（nil 或空字串是中斷連線）。沒存成功回 false，原本的不動
    @discardableResult
    func setBridge(_ url: String?) -> Bool {
        let clean: String = (url ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty {
            SecretStore.clear(.bridge)
            BRIDGE_URL = ""
        } else {
            guard SecretStore.save(.bridge, clean) else {
                show("連線沒有存成功，等一下再試一次。", false)
                return false
            }
            BRIDGE_URL = clean
        }
        bridgeSet = !BRIDGE_URL.isEmpty
        aiDest = aiDestNow()
        return true
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
            if let data, var state = AppState.hydrate(data) {
                // 舊檔的趟沒有代號，先補上
                syncAIUsed(&state)
                // 等回覆的時候 app 被結束的那句，不會再有回覆了
                markUnanswered(&state)
                s = state
                refillWishes()
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
    /// 寫完順便把排好的通知換成新的。沒寫成功會記著，下次改動或回到前景再寫一次
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
                    self?.saveFailed()
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

    /// 沒寫成功：還是沒存的，下次再寫
    private func saveFailed() {
        dirty = true
        show("這一步沒有存成功，手機的空間可能滿了。", false)
    }

    /// 行程、打勾、提醒開關有變，就把排好的通知整批換新。關掉提醒時是清空。內容跟上次一樣就不動
    private func syncReminderList() {
        guard ready else { return }
        let list: [Reminder] = s.remind ? remindersOf(remindState(s), today) : []
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
    /// 換掉現在這趟的動作不管有沒有寫都會留一步，不然之後復原會把別趟蓋掉；寫了才在提示條給「復原」。
    /// mark 是這一步的記號（跟 AI 講的那一輪用），之後拿 undoTop 比對還是不是最後一步
    func act(undoable: Bool = false, animated: Bool = true, mark: String? = nil, _ change: (inout AppState) -> String?) {
        let prev = s
        var draft = s
        let message: String? = change(&draft)
        // 剛開的一趟補代號；每一趟的句數只多不少
        syncAIUsed(&draft)
        let swap: Bool = tripSwapped(prev, draft)
        if undoable || swap {
            undoStack.append(undoSnap(prev, swap: swap, mark: mark))
            if undoStack.count > AppStore.undoMax {
                undoStack.removeFirst()
            }
            canUndo = true
            undoTop = mark
        }
        leaveTrip(draft.trip?.id)
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
        // 句數不在復原的範圍，規則在 Chat.swift 的 aiLeft
        let message: String = applyUndo(&next, snap)
        // 復原回來的對話裡，等不到回覆的那句要能再送一次
        if !talkBusy { markUnanswered(&next) }
        leaveTrip(next.trip?.id)
        withAnimation(Motion.change) {
            s = next
        }
        // 復原回來的照片不算拿掉了
        PhotoStore.keepUsed(next)
        save()
        show(message, false)
    }

    /// 現在沒有這趟，而且按復原會拿回一趟、那趟又不在其他排好的（不要這一版、收進去過的旅行）：是哪一趟。
    /// 給開一趟那一頁放復原，提示條過了還按得到
    var undoTrip: Trip? {
        guard s.trip == nil, canUndo, let snap = undoStack.last, let trip = snap.trip else { return nil }
        let onShelf: Bool = s.shelf.contains { (x: Shelved) -> Bool in x.trip.id == trip.id }
        return onShelf ? nil : trip
    }

    /// 要換到別趟之前：等同意的那句不送、留著，打到一半的字跟著原本那趟收好，換成那一趟的
    private func leaveTrip(_ next: String?) {
        let old: String? = s.trip?.id
        if old == next { return }
        if case .consent(let text, let ask) = talkStage {
            keepPending(text, ask)
        }
        if !talkBusy { talkStage = .idle }
        if let old {
            draftBox[old] = TalkDrafts(now: drafts, later: keptTalk, wishLine: wishLine)
        }
        var back: TalkDrafts = TalkDrafts()
        if let next, let box = draftBox.removeValue(forKey: next) {
            back = box
        }
        drafts = back.now
        keptTalk = back.later
        wishLine = back.wishLine
    }

    /// 開一趟時寫的、還沒送給 AI 的那句：打到一半的字只放在記憶體，重開 app 之後照行程裡記的放回第 1 天那一列
    private func refillWishes() {
        if let t = s.trip, let wish = heldWish(t, s.chat, s.debugDay) {
            drafts[.day(1)] = wish
        }
        for x in s.shelf {
            guard let id = x.trip.id, let wish = heldWish(x.trip, x.chat, x.debugDay) else { continue }
            var box: TalkDrafts = TalkDrafts()
            box.now[.day(1)] = wish
            draftBox[id] = box
        }
    }

    /// 還沒送的那句。自己拿掉的、改過字講的（wishStatus 不會是 held）不放；已經回來的那趟不用再放
    private func heldWish(_ t: Trip, _ chat: [ChatMsg], _ debugDay: Int?) -> String? {
        guard let wish = t.wish, wishStatus(t, chat, false) == WishStatus.held else { return nil }
        if phaseOf(t.start, t.days, today, debugDay) == Phase.done { return nil }
        return oneLine(wish)
    }

    /// 只顯示一句話，不改資料
    func say(_ text: String) {
        show(text, false)
    }

    func dismissNotice() {
        noticeTask?.cancel()
        notice = nil
    }

    /// 整包換掉（清除全部、匯入）。復原紀錄會清空。匯入的備份裡有同一趟，句數取多的。
    /// imported 為 true（貼上備份）時，送給 AI 的同意留這支手機自己的；false（全部清掉）一起清
    func replaceAll(_ next: AppState, imported: Bool) {
        var fresh: AppState = next
        carryAILog(&fresh, s)
        // 現在還用得到的照片不算拿掉了，之後貼回備份才看得到
        PhotoStore.keepUsed(s)
        markUnanswered(&fresh)
        if imported {
            keepAgreed(&fresh, s)
        } else {
            revokeAI(&fresh)
        }
        undoStack = []
        canUndo = false
        undoTop = nil
        // 還在等的那句不等了：回來的時候不套、也不動之後的狀態
        talkSeq += 1
        talkStage = .idle
        drafts = [:]
        keptTalk = [:]
        wishLine = nil
        draftBox = [:]
        startDraft = StartDraft()
        s = fresh
        refillWishes()
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
    /// 沒接 AI。只有再送一次開一趟時寫的那句才會有
    case noAI
}

/// 等同意的那一句
struct TalkPending: Equatable {
    /// 在哪裡講的
    let target: TalkTarget
    /// 說明上寫的、要他同意送去的那個地方
    let dest: AIDest
    /// 等他按的時候地方換了，這是重新問的
    var moved: Bool = false
    /// 沒收到回覆、要再送一次的那句在對話裡第幾則。新的一句是 nil
    var retry: Int?
    /// 開一趟按「幫我排」送的那句。按先不要的時候，要講清楚行程在、那句沒送
    var wish: Bool = false
}

/// 開一趟時寫的那句沒送給 AI 的原因
enum WishHold: Equatable {
    case offline
    case quota
    /// 沒接 AI，本機指令也做不了
    case noAI
    /// 按了先不要
    case declined
}

enum TalkStage: Equatable {
    case idle
    /// 第一次要送到這個地方：等「同意並送出」（S03，線框 New-Consent）
    case consent(text: String, ask: TalkPending)
    /// 要 AI 的這句沒有送出去。again 是 false：新的一句，字留在講的那一列；
    /// true：再送一次的那句，字本來就在對話裡，講的那一列沒有
    case held(TalkHold, again: Bool)
    /// 剛開好一趟，寫的那句沒有送出去，字留在第 1 天講的那一列。行程已經排好
    case wishHeld(WishHold)
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
        if !aiOn { return nil }
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

    /// 按了再送一次、還是沒送出去的原因。沒有這回事是 nil
    var talkAgainWhy: String? {
        guard case .held(let why, again: let again) = talkStage, again else { return nil }
        switch why {
        case .offline:
            return "剛剛沒網路，這句沒有再送出去，還在對話裡。連上網路再按一次。"
        case .quota:
            return "這趟的 AI 句數用完了，這句沒有再送出去，還在對話裡。"
        case .noAI:
            return "現在沒有接 AI，這句沒有再送出去，還在對話裡。到「平常的我」接上 AI 再按一次。"
        }
    }

    /// 講的那一列打字（輸入框用，送出不走這裡）。第 1 天那一列放著開一趟時寫的那句的話，
    /// 記下他是不是自己拿掉了：拿掉了，重開 app 就不再塞回來
    func typeDraft(_ target: TalkTarget, _ next: String) {
        let old: String = drafts[target] ?? ""
        if old == next { return }
        drafts[target] = next
        guard target == TalkTarget.day(1), let trip = s.trip else { return }
        let step: WishTyped = wishTyped(trip, s.chat, old, next, wishLine)
        wishLine = step.line
        if step.off == trip.wishOff { return }
        let off: WishOff? = step.off
        mutate { (d: inout AppState) -> Void in
            setWishOff(&d, off)
        }
    }

    /// 這句講出去了（記進對話了）。回 true：它是從開一趟時寫的那句改出來的，原本那句就不用再留
    private func wishEdited(_ msg: String, _ target: TalkTarget, _ whole: Bool) -> Bool {
        guard target == TalkTarget.day(1), wishFromLine(wishLine, msg) else { return false }
        wishLine = nil
        return !whole
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
        if talkWhole(text, target) { return wishPhone(text, s, talkNow) }
        return phoneAnswer(text, s, talkDayOf(target), talkStopId(target), talkNow)
    }

    /// 這句是不是開一趟時寫的、還沒送成的那句。是的話講的是整趟，不照在看的那一天聽
    private func talkWhole(_ text: String, _ target: TalkTarget) -> Bool {
        guard case .day = target, let trip = s.trip else { return false }
        return wishPending(trip, s.chat, text)
    }

    /// 那句現在沒有人可以處理：沒接 AI，手機答不出、本機指令也做不了
    private func wishNoAI(_ text: String, _ target: TalkTarget) -> Bool {
        guard aiDest == nil, let trip = s.trip else { return false }
        if talkWantsRegen(text) || talkPhone(text, target: target) != nil { return false }
        return !wishLocalCan(text, trip, talkNow)
    }

    /// 開一趟時寫的那句：行程已經排好、存好了，再當第一句走跟講的那一列一樣的流程（talk）。
    /// 送不出去就把字放在第 1 天那一列。回 true：要升起剛剛那一則（等同意、等回覆、答了、講清楚沒有送）
    func talkWish() -> Bool {
        guard let wish = s.trip?.wish, !wish.isEmpty else { return false }
        let target: TalkTarget = .day(1)
        if talkBusy {
            keepDraft(wish, target)
            show("行程排好了。上一句還在等回覆，你寫的那句還沒有送給 AI，留在第 1 天講的那一列。", false)
            return false
        }
        if wishNoAI(wish, target) {
            keepDraft(wish, target)
            talkStage = .wishHeld(.noAI)
            return true
        }
        talk(wish, target: target)
        switch talkStage {
        case .consent(let text, let ask):
            var first: TalkPending = ask
            first.wish = true
            talkStage = .consent(text: text, ask: first)
        case .held(let why, again: _):
            talkStage = .wishHeld(why == .offline ? WishHold.offline : WishHold.quota)
        case .idle, .busy, .wishHeld:
            break
        }
        return true
    }

    /// 這句要不要送給 AI：手機答不出、又有接 AI。沒網路、句數用完時，這種句子送不出去
    func talkNeedsAI(_ text: String, target: TalkTarget) -> Bool {
        if !aiOn || talkWantsRegen(text) { return false }
        return talkPhone(text, target: target) == nil
    }

    /// 講的那一列上面那排說法，照這趟走到哪換（02-流程 5-3）。
    /// 沒接 AI 的時候，換成本機指令聽得懂的
    func talkHints(_ target: TalkTarget) -> [String] {
        let remote: Bool = aiOn
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
        // 上一句還在等同意：那句沒送，字留著
        if case .consent(let old, let ask) = talkStage {
            keepPending(old, ask)
            talkStage = .idle
        }
        let day: Int = talkDayOf(target)
        let stop: String? = talkStopId(target)
        let whole: Bool = talkWhole(msg, target)
        if let answer = talkPhone(msg, target: target) {
            talkStage = .idle
            let stamp: Double = Date().timeIntervalSince1970
            var mine: ChatMsg = ChatMsg(r: .me, t: msg, day: day, stop: stop)
            mine.wish = whole ? true : nil
            let said: ChatMsg = mine
            let edited: Bool = wishEdited(msg, target, whole)
            mutate { (d: inout AppState) -> Void in
                if edited { setWishOff(&d, .edited) }
                d.chat.append(said)
                d.chat.append(ChatMsg(r: .ai, t: answer, day: day, stop: stop, local: true, at: stamp))
            }
            return true
        }
        // 只是叫整趟重排：手機自己做，不送 AI、不算句數、不用網路
        if talkWantsRegen(msg) {
            talkSend(msg, target, nil, retry: nil)
            return true
        }
        // 開一趟時寫的那句，本機指令聽不懂就留著，等接上 AI 再送
        if whole && wishNoAI(msg, target) {
            keepDraft(msg, target)
            talkStage = .idle
            show("現在沒有接 AI，這句還沒有送出去，字留著。", false)
            return false
        }
        let dest: AIDest? = aiDest
        if let dest {
            if let hold = talkHold {
                keepDraft(msg, target)
                talkStage = .held(hold, again: false)
                Haptic.notify(.error)
                return false
            }
            if !aiAllowed(s, dest) {
                talkStage = .consent(text: msg, ask: TalkPending(target: target, dest: dest))
                return true
            }
        }
        talkSend(msg, target, dest, retry: nil)
        return true
    }

    /// 說明按「同意並送出」。shown 是按下去那一刻畫面上寫的地方：記的是它，也只送去它。
    /// 等他按的時候地方換了就不送、不記，照新的地方重新問
    func talkConsent(_ shown: AIDest) {
        guard case .consent(let text, let ask) = talkStage else { return }
        switch consentStep(shown, aiDestNow()) {
        case .askAgain(let now):
            var again: TalkPending = TalkPending(target: ask.target, dest: now, moved: true)
            again.retry = ask.retry
            again.wish = ask.wish
            talkStage = .consent(text: text, ask: again)
            Haptic.notify(.error)
        case .gone:
            keepPending(text, ask)
            if ask.wish {
                talkStage = .wishHeld(.noAI)
            } else {
                talkStage = .idle
                show("現在沒有接 AI，這句沒有送出去。", false)
            }
        case .send(let dest):
            mutate { (d: inout AppState) -> Void in
                agreeAI(&d, dest)
            }
            talkStage = .idle
            if let hold = talkHold {
                keepPending(text, ask)
                if ask.wish {
                    talkStage = .wishHeld(hold == .offline ? WishHold.offline : WishHold.quota)
                } else {
                    var again: Bool = false
                    if let i = ask.retry { again = canRetry(i, text) }
                    talkStage = .held(hold, again: again)
                }
                Haptic.notify(.error)
                return
            }
            if let i = ask.retry, !canRetry(i, text) {
                // 等同意的時候換了一趟、對話清掉了：那句不在了，不送
                keepPending(text, ask)
                return
            }
            talkSend(text, ask.target, dest, retry: ask.retry)
        }
    }

    /// 說明按「先不要」：什麼都不送，講的字放回那一列。開一趟寫的那句再講清楚行程在、那句沒送
    func talkDecline() {
        guard case .consent(let text, let ask) = talkStage else { return }
        keepPending(text, ask)
        talkStage = ask.wish ? TalkStage.wishHeld(.declined) : TalkStage.idle
    }

    /// 等同意的那句沒送：字放回那一列。再送一次的那句本來就還在對話裡，不用放
    private func keepPending(_ text: String, _ ask: TalkPending) {
        if let i = ask.retry, canRetry(i, text) { return }
        keepDraft(text, ask.target)
    }

    /// 對話裡第 index 則還是那句沒收到回覆的
    private func canRetry(_ index: Int, _ text: String) -> Bool {
        guard index >= 0, index < s.chat.count else { return false }
        let m: ChatMsg = s.chat[index]
        return m.r == .me && m.t == text && m.failed != nil
    }

    /// 剛剛那一則收起來的時候：還在等同意的當作先不要；沒送出去的那句已經留在那一列了
    func talkDismiss() {
        switch talkStage {
        case .consent:
            talkDecline()
            // 開一趟寫的那句，往下滑掉說明：半頁沒了，用提示條講
            if case .wishHeld = talkStage {
                talkStage = .idle
                show("行程排好了。你寫的那句沒有送給 AI，留在第 1 天講的那一列。", false)
            }
        case .held, .wishHeld:
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
        // 有別句在等同意：那句沒送，字留著
        if case .consent(let old, let pending) = talkStage {
            keepPending(old, pending)
            talkStage = .idle
        }
        if talkWantsRegen(m.t) {
            talkSend(m.t, target, nil, retry: index)
            return
        }
        // 開一趟時寫的那句，沒接 AI 時本機指令做不了：不送，留在對話裡
        if m.wish == true && wishNoAI(m.t, target) {
            talkStage = .held(.noAI, again: true)
            Haptic.notify(.error)
            return
        }
        if let hold = talkHold {
            talkStage = .held(hold, again: true)
            Haptic.notify(.error)
            return
        }
        // 收回同意、換了地方之後再送一次，也要先問
        if let dest = aiDest, !aiAllowed(s, dest) {
            var ask: TalkPending = TalkPending(target: target, dest: dest)
            ask.retry = index
            talkStage = .consent(text: m.t, ask: ask)
            return
        }
        talkSend(m.t, target, aiDest, retry: index)
    }

    /// 那一列是空的才把字放回去，不蓋掉他正在打的；正在打別的就先收著，那一列空了再放（keptBack）
    private func keepDraft(_ msg: String, _ target: TalkTarget) {
        let typed: String = (drafts[target] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // 那一列只有一行
        let line: String = oneLine(msg)
        if typed.isEmpty {
            drafts[target] = line
        } else if typed != line {
            var list: [String] = keptTalk[target] ?? []
            if !list.contains(line) { list.append(line) }
            keptTalk[target] = list
        }
    }

    /// 那一列送出去、空了：之前沒送出去、收著的那句放回來
    func keptBack(_ target: TalkTarget) {
        let typed: String = (drafts[target] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.isEmpty, var list = keptTalk[target], !list.isEmpty else { return }
        drafts[target] = list.removeFirst()
        keptTalk[target] = list
    }

    /// 真的送出去：先記下我說的（再送一次就清掉沒收到的記號），再問 AI 或本機指令，回來再套上改動。
    /// dest 是同意過的那個地方，nil 是沒接 AI（走本機指令）。送的那一刻地方換了，askAI 會擋下來
    private func talkSend(_ msg: String, _ target: TalkTarget, _ dest: AIDest?, retry: Int?) {
        guard let trip = s.trip else { return }
        let day: Int = talkDayOf(target)
        let stop: String? = talkStopId(target)
        let settings: Settings = s.settings
        // 送給 AI 的前面幾句不含這一句（這一句在提示詞裡另外寫）
        var history: [ChatMsg] = s.chat
        if let i = retry { history = Array(s.chat.prefix(i)) }
        // 按下去那一刻的「現在」：AI 和套用改動都用同一個，免得送出到回來之間跨過時段
        let clock: ChatClock? = phase.map { (p: Phase) -> ChatClock in chatClock(p) }
        // 開一趟時寫的那句講的是整趟：不說在看哪一天，本機指令也不補「第 1 天」
        var whole: Bool = talkWhole(msg, target)
        if let i = retry, i < s.chat.count { whole = s.chat[i].wish == true }
        let focus: String = whole ? WISH_FOCUS : talkFocus(trip, stop == nil ? day : nil, stop)
        let heard: String = whole ? msg : talkLocal(msg, trip, day, stop, stop == nil)
        var mine: ChatMsg = ChatMsg(r: .me, t: msg, day: day, stop: stop)
        mine.wish = whole ? true : nil
        let saying: ChatMsg = mine
        let edited: Bool = retry == nil && wishEdited(msg, target, whole)
        talkSeq += 1
        let seq: Int = talkSeq
        talkStage = .busy
        mutate { (d: inout AppState) -> Void in
            if edited { setWishOff(&d, .edited) }
            // 還沒按的確認卡過期：行程接下來會變，那幾步不一定還對
            for i in d.chat.indices where d.chat[i].askOps != nil {
                d.chat[i].askOps = nil
                d.chat[i].asked = false
            }
            if let i = retry, i < d.chat.count {
                d.chat[i].failed = nil
            } else {
                d.chat.append(saying)
            }
        }
        let me: Int = retry ?? (s.chat.count - 1)
        let tripId: String? = trip.id
        Task { @MainActor in
            if let dest {
                do {
                    let prompt: String = aiPrompt(msg, trip, settings, history, clock, focus)
                    let out: BrainOut = try await askAI(prompt, dest)
                    self.countAISentence(trip.id)
                    if self.talkSeq != seq { return }
                    self.talkFinish(out, local: false, tripId: tripId, me: me, said: msg, day: day, stop: stop, clock: clock)
                } catch {
                    // 沒回好、讀不懂：這趟不動，不退回本機指令（線框 A21）
                    if self.talkSeq != seq { return }
                    self.talkFail(tripId: tripId, me: me, said: msg, error)
                }
            } else {
                let out: BrainOut = localBrain(heard, trip, tripNow(clock))
                if self.talkSeq != seq { return }
                self.talkFinish(out, local: true, tripId: tripId, me: me, said: msg, day: day, stop: stop, clock: clock)
            }
            self.talkStage = .idle
            self.talkLost()
        }
    }

    /// 剛剛那句回來了，現在沒有句子在等。等的時候復原回來的對話裡要是還有沒人回的，補上再送一次
    private func talkLost() {
        var probe: AppState = s
        if !markUnanswered(&probe) { return }
        mutate { (d: inout AppState) -> Void in
            markUnanswered(&d)
        }
    }

    /// 把回來的動作套到行程上，對話裡記下改了什麼、每一天差多少、哪幾步沒做成。有改到行程才留復原
    private func talkFinish(
        _ out: BrainOut, local: Bool, tripId: String?, me: Int, said msg: String, day: Int, stop: String?, clock: ChatClock?
    ) {
        // 等回覆的時候這趟換了、對話清掉了：回來的不套
        guard let current = s.trip, current.id == tripId, isSaid(s.chat, me, msg) else {
            talkAway(out, local: local, tripId: tripId, me: me, said: msg, day: day, stop: stop)
            return
        }
        let now: TripNow? = tripNow(clock)
        // 旅途中、有去過的站（回來之後也是）不整趟重排：去過的站會被洗掉
        let blockRegen: Bool = out.regen == true && (now != nil || tripVisited(current))
        let blockText: String = now != nil ? NO_REGEN_ON_TRIP : NO_REGEN_VISITED
        // 本機指令回的是「好，整趟重排一次。」，沒重排就不能這樣回
        let reply: String = blockRegen && local ? blockText : out.reply
        let regen: Bool = out.regen == true && !blockRegen
        // 開一趟時寫的那句：照它改了哪些記在這一版上，剛排好那張卡要寫
        let whole: Bool = s.chat[me].wish == true
        let fresh: Bool = whole && !regen && PlannedSeen.fresh(current)
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
                trip = replanTrip(trip, draftOf(trip), d.settings, true)
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
            if whole && !changes.isEmpty {
                trip.wishChanges = changes
                // 那張卡還在的話就留著：記成照那句改完的樣子，之後再改才收掉
                if fresh { trip.planMark = planMarkOf(trip) }
                d.trip = trip
            }
            if !regen && !r.changes.isEmpty {
                changes.append(contentsOf: dayDeltas(before, trip, d.settings))
            }
            var said: ChatMsg = ChatMsg(r: .ai, t: reply, changes: changes, day: day, stop: stop)
            said.local = local ? true : nil
            said.at = stamp
            if regen || !r.changes.isEmpty { said.undo = mark }
            if !split.confirm.isEmpty {
                let after: Trip = trip
                said.ask = split.confirm.map { (o: [String: Any]) -> String in opLine(after, o) }
                said.askOps = packOps(split.confirm)
            }
            d.chat.append(said)
            if blockRegen && !local {
                d.chat.append(ChatMsg(r: .sys, t: blockText))
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
        if fresh, let made = s.trip?.planMark {
            PlannedSeen.marks.insert(made)
        }
    }

    /// 回來的時候已經換到別趟：回的話留在原本那一趟的對話裡，改動不套，現在這趟講一聲
    private func talkAway(
        _ out: BrainOut, local: Bool, tripId: String?, me: Int, said msg: String, day: Int, stop: String?
    ) {
        guard let tripId else { return }
        var reply: ChatMsg = ChatMsg(r: .ai, t: out.reply, day: day, stop: stop)
        reply.local = local ? true : nil
        reply.at = Date().timeIntervalSince1970
        let hadChanges: Bool = out.regen == true || !out.ops.isEmpty
        act { (d: inout AppState) -> String? in
            guard let name = leaveReply(&d, tripId, me, msg, reply, hadChanges) else { return nil }
            return hadChanges ? "「\(name)」的那句有回覆了，改動沒有套上去。" : "「\(name)」的那句有回覆了，切回去看得到。"
        }
    }

    /// 沒收到回覆：這趟不動，在我說的那句記下來，可以再送一次
    private func talkFail(tripId: String?, me: Int, said msg: String, _ error: Error) {
        Haptic.notify(.error)
        let code: String = talkErrorCode(error)
        mutate { (d: inout AppState) -> Void in
            if d.trip?.id == tripId {
                guard isSaid(d.chat, me, msg) else { return }
                d.chat[me].failed = code
            } else if let tripId {
                leaveFail(&d, tripId, me, msg, code)
            }
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
            if tweaked && now == nil && !tripVisited(trip) {
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
