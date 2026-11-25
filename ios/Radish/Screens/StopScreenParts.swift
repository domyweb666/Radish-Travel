// 一站（StopScreen.swift）的每一塊：最上面那一行、為什麼排／須知／花費、過敏、去過之後的那一句和照片、
// （開放、怎麼訂、來源在 Components/StopFacts.swift）
// 韓文名、想改這一站、別的找路方式，還有這一頁自己開的兩張半頁：換一個、不去這一站。
// 原本在 mobile/src/sheets/StopSheet.tsx（SwiftUI 版的 Sheets/StopSheetParts.swift），字照搬，版面照線框 A5。
import SwiftUI
import UIKit

// MARK: - 最上面那一行

/// 大標題下面：第幾天、哪天、哪個時段、哪一帶、哪一種，和狀態小標籤
struct StopHeader: View {
    @Environment(AppStore.self) private var store
    let it: Stop
    let trip: Trip
    let slot: Slot
    /// 這一站那天去不了（休館、歇業）。去得了是 nil
    let shut: StopShut?
    /// 排的這個時段不開。開、或那天整天不開是 nil
    let partShut: String?
    /// 那天要注意、但不算不開的。沒有是 nil
    let caution: String?

    private var line: String {
        let date: String = fmtDay(addDays(trip.start, slot.day - 1))
        return "第 \(slot.day) 天・\(date)\(PART[need: slot.part])・\(areaOf(it))・\(kindName(it))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            HStack(alignment: .center, spacing: T.Space.s3) {
                CatIcon(it)
                DomyText(line, .subheadline, tone: .secondary)
                    .fillLeading()
            }
            if let warn {
                WarnTag(warn)
                    .accessibilityIdentifier("stop-closed")
            } else if let partShut {
                WarnTag(partShut)
                    .accessibilityIdentifier("stop-part-closed")
            }
            if let caution {
                WarnTag("這天要注意：\(caution)")
                    .accessibilityIdentifier("stop-caution")
            }
            tags
        }
    }

    /// 那天去不了，原因寫在這裡，下面「開放」那組不再講一次
    private var warn: String? {
        guard let shut else { return nil }
        if shut.gone { return shut.why }
        return "這天\(kindWords(it.c).shut)：\(shut.why)"
    }

    private var tags: some View {
        let st: Settings = tripSettings(store.s.settings, trip.tweaks)
        return TagRow {
            Tag(it.s == .L ? "主要景點" : "順路小地方")
            if needsBook(it) {
                Tag("要先訂", tone: .accent)
            }
            if it.ai == true {
                Tag("AI 加的・未核對", tone: .warn)
            }
            if it.mine == true {
                Tag("自己加的")
            }
            if it.status == .pulled {
                Tag("去過了", tone: .accent)
            }
            if it.up == true && st.body.contains(.stairs) {
                Tag("坡多或階梯多", tone: .warn)
            }
        }
    }
}

// MARK: - 為什麼排、須知、花費

struct StopInfoSection: View {
    let it: Stop
    /// 下面有「開放」那組。沒有的話，這一組底下要講營業時間得自己查
    let hasOpen: Bool
    /// 要先訂但沒查到怎麼訂
    let noBook: Bool

    private var whyText: String {
        it.why.isEmpty ? "這一站沒有寫為什麼排。" : it.why
    }

    /// 核對過的須知優先，沒有才用資料包那句
    private var tipText: String? {
        guard let tip = tipOf(it) else { return nil }
        return fullStop(tip.text)
    }

    /// 資料包那句還沒核對的，跟核對過的分開放
    private var extraText: String? {
        guard let tip = tipOf(it), let extra = tip.extra, !extra.isEmpty else { return nil }
        return fullStop(extra)
    }

    /// 票價（有查到才有）和原本的粗估，各一行
    private var feeText: String? {
        var parts: [String] = []
        if let f = factOf(it.id), let price = f.price, !price.isEmpty {
            parts.append("\(priceLead(f.status))：\(price)")
        }
        if let fee = it.fee, fee != 0 {
            let tail: String = parts.isEmpty ? "（粗估，沒核對過）" : "（粗估）"
            parts.append("每人約 \(money(fee))\(tail)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n")
    }

    private func priceLead(_ status: FactStatus) -> String {
        let word: String = kindWords(it.c).price
        switch status {
        case FactStatus.official: return "官方" + word
        case FactStatus.second: return word + "（二手資料）"
        case FactStatus.none: return word + "（未核對）"
        }
    }

    private var footer: String? {
        if noBook {
            return hasOpen ? "怎麼訂還沒查到，去之前自己查一下。" : "怎麼訂、營業時間都還沒查到，去之前自己查一下。"
        }
        if hasOpen { return nil }
        return "照片、招牌菜、平均消費、營業時間，要等接上地點查證才有。現在去之前請自己查一下。"
    }

    var body: some View {
        let tip: String? = tipText
        let fee: String? = feeText
        DomySection(footer: footer) {
            StopInfoRow(label: "為什麼排", text: whyText)
            StopInfoRow(
                label: "須知", text: tip ?? "這一站還沒有須知。", tag: tip == nil ? nil : tipSourceLabel(it),
                muted: tip == nil)
            if let extra = extraText {
                StopInfoRow(label: "另一句須知", text: extra, tag: "未核對")
            }
            StopInfoRow(label: "花費", text: fee ?? "還沒有資料", muted: fee == nil)
        }
    }
}

/// 卡片裡的一列：上面小標（後面可以跟一個核對到哪裡的小標籤），下面內容
struct StopInfoRow: View {
    let label: String
    let text: String
    var tag: String? = nil
    var muted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
            HStack(spacing: T.Space.s2) {
                FieldLabel(label)
                if let tag {
                    Tag(tag)
                }
            }
            DomyText(text, .body, tone: muted ? .secondary : .primary)
        }
        .padding(.vertical, T.Space.s3)
        .fillLeading()
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 過敏

/// 吃的站，而且設了過敏：說清楚 app 幫不了什麼，給一個打開告知卡的入口（S15）
struct StopAllergyEntry: View {
    @Environment(AppStore.self) private var store
    let it: Stop
    let trip: Trip
    let onOpen: () -> Void

    var body: some View {
        let allergy: [String] = tripSettings(store.s.settings, trip.tweaks).allergy
        let eats: Bool = it.c == .eat || it.c == .cafe
        if eats && !allergy.isEmpty {
            Card {
                FieldLabel("你有過敏：\(allergy.joined(separator: "、"))")
                DomyText("這一站我不知道店裡用了哪些食材，沒辦法幫你排除。點餐前把告知卡拿給店員看，自己確認。")
                DomyButton("打開過敏告知卡", variant: .secondary, size: .compact, action: onOpen)
                    .accessibilityIdentifier("stop-allergy")
            }
        }
    }
}

// MARK: - 去過之後：那一句、照片

struct StopVisitBlock: View {
    @Environment(AppStore.self) private var store
    let id: String
    let it: Stop
    /// 這一塊畫的是哪一趟。換了一趟，框裡打到一半的是上一趟的
    let tripId: String?

    var body: some View {
        if it.status == .pulled {
            VStack(alignment: .leading, spacing: T.Space.s4) {
                VisitNote(
                    say: it.say,
                    photos: it.photos ?? [],
                    onSay: { (say: String) -> Void in saveSay(say) },
                    onAdd: { (ref: String) -> Void in addPhoto(ref) },
                    onRemove: { (ref: String) -> Void in removePhoto(ref) })
            }
            // 換了一趟就換一個新的框，上一趟打的字不會帶到這一趟
            .id(tripId ?? "")
        }
    }

    /// 這一塊畫出來之後換了一趟（例：按了提示條的復原）
    private var moved: Bool {
        return store.s.trip?.id != tripId
    }

    /// 這一站現在的樣子。被拿掉、換掉了就是 nil
    private var now: Stop? {
        guard let trip = store.s.trip else { return nil }
        return findItem(trip, id)?.it
    }

    private func saveSay(_ say: String) {
        // 沒有存的話把那一句寫在提示條上，還來得及抄
        if moved {
            if !say.isEmpty { store.say("剛剛換到別趟了，這一句沒有存：「\(say)」") }
            return
        }
        guard let stop = now else {
            if !say.isEmpty { store.say("這一站不在這趟裡了，這一句沒有存：「\(say)」") }
            return
        }
        // 沒有變就不留一步
        if (stop.say ?? "") == say { return }
        change(say.isEmpty ? "那一句清掉了。" : "那一句記下來了。") { (x: inout Stop) -> Void in
            x.say = say
        }
    }

    /// 照片處理完才叫，中間清單可能變過，所以照現在的清單加
    private func addPhoto(_ ref: String) {
        if moved {
            PhotoStore.removeLater(ref)
            store.say("剛剛換到別趟了，照片沒有加上去。")
            return
        }
        guard let stop = now else {
            PhotoStore.removeLater(ref)
            store.say("這一站不在這趟裡了，照片沒有加上去。")
            return
        }
        if (stop.photos ?? []).count >= PhotoStore.max {
            PhotoStore.removeLater(ref)
            store.say("這一站已經有 \(PhotoStore.max) 張了，這張沒有加上去。")
            return
        }
        change("加了一張照片。") { (x: inout Stop) -> Void in
            var list: [String] = x.photos ?? []
            list.append(ref)
            x.photos = list
        }
    }

    /// 只拿掉引用，檔案留到下次開 app 才刪，中間都能復原
    private func removePhoto(_ ref: String) {
        guard !moved, let stop = now else { return }
        let old: [String] = stop.photos ?? []
        if !old.contains(ref) { return }
        change("照片拿掉了。") { (x: inout Stop) -> Void in
            let list: [String] = x.photos ?? []
            x.photos = list.filter { (p: String) -> Bool in p != ref }
        }
        PhotoStore.removeLater(ref)
    }

    /// 改這一站，留一步可以復原
    private func change(_ msg: String, _ edit: (inout Stop) -> Void) {
        let stopId: String = id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let x = findItem(trip, stopId) else { return nil }
            edit(&trip.slots[x.si].items[x.ii])
            d.trip = trip
            return msg
        }
    }
}

// MARK: - 韓文名、找路

/// 有韓文名：放大給司機看、用 Naver 找路。沒有韓文名（挑一間、自己加的）就講清楚為什麼沒有，也不出現給司機看
struct StopPlaceCard: View {
    let it: Stop
    let onDriver: () -> Void

    var body: some View {
        if !it.kr.isEmpty {
            Card {
                FieldLabel("韓文名（給司機或路人看）")
                DomyText(it.kr, .title2)
                // 字級放大時兩顆放不下，改成一顆一列
                PairLayout(spacing: T.Space.s2) {
                    DomyButton("放大給司機看", variant: .secondary, size: .compact, fullWidth: true, action: onDriver)
                        .accessibilityIdentifier("stop-show")
                    DomyButton("用 Naver 找路", variant: .secondary, size: .compact, fullWidth: true) {
                        openNaver(it.kr)
                    }
                    .accessibilityIdentifier("stop-naver")
                }
            }
        } else {
            Card {
                DomyText(
                    (it.mine == true ? "這是你自己加的，這一版還不知道它在哪。" : "這一站目前只排到「哪一帶、吃哪一種」，還沒有指定店家。")
                        + "接上地點查證後，會給店名、韓文地址和地圖連結。",
                    .subheadline, tone: .secondary)
            }
        }
    }
}

/// 最下面：複製韓文、Google、Apple 地圖。線框 A5 只畫了 Naver，原本卡上的這三個留在這裡
struct StopOtherMaps: View {
    let it: Stop
    @State private var copied: Bool = false

    /// 查到韓文地址的站，地址在「放大給司機看」
    private var footer: String? {
        if factOf(it.id)?.addr != nil { return nil }
        return "這一版只有韓文名稱，沒有門牌地址。接上地點查證後會帶出完整韓文地址。"
    }

    var body: some View {
        if !it.kr.isEmpty {
            DomySection("別的找路方式", footer: footer) {
                SettingsRow("複製韓文名", value: copied ? "複製了" : nil) {
                    UIPasteboard.general.string = it.kr
                    copied = true
                }
                .accessibilityIdentifier("stop-copy")
                SettingsRow("用 Google 地圖開") { openGoogle(it.kr) }
                    .accessibilityIdentifier("stop-google")
                SettingsRow("用 Apple 地圖開") { openApple(it.kr) }
                    .accessibilityIdentifier("stop-apple")
            }
        }
    }
}

// MARK: - 想改這一站

/// 還沒去：（出發後）拔起來、移到別的時段、換一個。去過了：按錯了改回來
struct StopEditBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    let id: String
    let it: Stop
    let trip: Trip
    let onSwap: () -> Void

    /// 出發之後每一站都可以標成去過：不照順序走、忘記按、回來才補，都從這裡
    private var started: Bool {
        guard let phase = store.phase else { return false }
        switch phase {
        case .plan: return false
        case .trip: return true
        case .done: return true
        }
    }

    var body: some View {
        if it.status == .kept {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                if started {
                    DomyButton("去過了，拔起來", fullWidth: true) {
                        setStatus(.pulled, "「\(it.n)」拔起來了。往下可以寫一句、加照片。")
                    }
                    .accessibilityIdentifier("stop-pull")
                    .padding(.bottom, T.Space.s4)
                }
                FieldLabel("想改這一站")
                    .padding(.horizontal, T.Space.s1)
                PairLayout(spacing: T.Space.s2) {
                    DomyButton("移到別的時段", variant: .secondary, size: .compact, fullWidth: true) {
                        sheets.open(.move(id: id))
                    }
                    .accessibilityIdentifier("stop-move")
                    DomyButton("換一個", variant: .secondary, size: .compact, fullWidth: true, action: onSwap)
                        .accessibilityIdentifier("stop-swap")
                }
            }
        } else {
            DomyButton("按錯了，這站還沒去", variant: .plain, fullWidth: true) {
                setStatus(.kept, "「\(it.n)」改回還沒去。寫的那一句和照片都還在。")
            }
            .accessibilityIdentifier("stop-unpull")
        }
    }

    private func setStatus(_ status: StopStatus, _ msg: String) {
        let stopId: String = id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let x = findItem(trip, stopId) else { return nil }
            trip.slots[x.si].items[x.ii].status = status
            d.trip = trip
            return msg
        }
    }
}

// MARK: - 換一個（半頁）

struct StopSwapPane: View {
    @Environment(AppStore.self) private var store
    let it: Stop
    let trip: Trip
    let onPick: (Place) -> Void
    let onClose: () -> Void

    var body: some View {
        let alts: [Place] = alternatives(trip, store.s.settings, it)
        SheetScaffold("把「\(it.n)」換成", onClose: onClose) {
            if it.swaps >= 3 {
                Card {
                    DomyText("這一站已經換過三輪了。前面那幾個都合你的條件，挑一個就好。想要完全不同的，用講的跟我說。")
                }
            } else if !alts.isEmpty {
                DomySection(footer: footer(alts.count)) {
                    ForEach(alts, id: \.id) { (p: Place) in
                        DomyListRow(meta: meta(p), title: p.n) {
                            onPick(p)
                        }
                        .accessibilityIdentifier("stop-swap-\(p.id)")
                    }
                }
            } else {
                Card {
                    DomyText(emptyText)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// 一個都挑不出來：是真的沒有，還是有、但這一站排的那個時段都不開
    private var emptyText: String {
        let head: String = it.a == nil ? "" : "這一帶"
        let all: [Place] = alternatives(
            trip, store.s.settings, it,
            closed: { (_: String, _: String) -> String? in nil },
            parts: { (_: String, _: String, _: Part) -> String? in nil })
        if let at = findItem(trip, it.id)?.s, !all.isEmpty {
            return "\(head)有別的候選，但第 \(at.day) 天\(PART[need: at.part])都不開。"
        }
        return "\(head)沒有別的候選了。"
    }

    /// 自己加的、AI 加的站沒有記在哪一帶，候選是從全首爾挑的
    private func footer(_ count: Int) -> String {
        if it.a == nil {
            return "這一站沒有記在哪一帶，這 \(count) 個是從全首爾挑的，差不多大小。一站最多換三輪。"
        }
        return "這一帶和旁邊，差不多大小的 \(count) 個。一站最多換三輪。"
    }

    private func meta(_ p: Place) -> String {
        var out: String = "\(kindName(p))・\(AREA[need: p.a])"
        if p.b == true {
            out += "・要先訂"
        }
        if let fee = p.fee, fee != 0 {
            out += "・約 " + money(fee)
        }
        return out
    }
}

// MARK: - 不去這一站（半頁）

/// 是這次不想去，還是以後都不要排。choice 傳 nil 是只這次
struct StopDropPane: View {
    let it: Stop
    let choices: [LearnChoice]
    let onPick: (LearnChoice?) -> Void
    let onClose: () -> Void

    var body: some View {
        SheetScaffold("不去「\(it.n)」", onClose: onClose) {
            DomyText("是這次不想去，還是以後都不要排？")
            DomyButton("只是這次不想，放到下次再來", fullWidth: true) {
                onPick(nil)
            }
            .accessibilityIdentifier("stop-drop-once")
            ForEach(choices, id: \.kind) { (c: LearnChoice) in
                DomyButton(
                    c.kind == .place ? "以後不排這一站" : "以後不排「\(c.n)」",
                    variant: .secondary, fullWidth: true
                ) {
                    onPick(c)
                }
                .accessibilityIdentifier("stop-drop-\(c.kind.rawValue)")
            }
            DomyButton("算了，留著", variant: .plain, fullWidth: true, action: onClose)
                .accessibilityIdentifier("stop-drop-cancel")
            DomyText(
                "選「以後不排」的話，之後每一趟排行程、換一個的時候都會跳過；有引號的那一顆是整個類別都不排。記下來的在「平常的我」→「從行程學到的」，隨時可以拿掉。",
                .footnote, tone: .secondary)
        }
        .presentationDetents([.medium, .large])
    }
}
