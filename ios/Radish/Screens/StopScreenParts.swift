// 一站（StopScreen.swift）的每一塊：最上面那一行、為什麼排／須知／花費、過敏、去過之後的那一句和照片、
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
            tags
        }
    }

    private var tags: some View {
        let st: Settings = tripSettings(store.s.settings, trip.tweaks)
        return TagRow {
            Tag(it.s == .L ? "主要景點" : "順路小地方")
            if it.b == true {
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

    private var whyText: String {
        it.why.isEmpty ? "這一站沒有寫為什麼排。" : it.why
    }

    private var hasTip: Bool {
        if let tip = it.tip, !tip.isEmpty { return true }
        return false
    }

    private var tipText: String {
        if let tip = it.tip, !tip.isEmpty {
            return "\(tip)。"
        }
        return "這一站還沒有須知。"
    }

    private var hasFee: Bool {
        if let fee = it.fee, fee != 0 { return true }
        return false
    }

    private var feeText: String {
        if let fee = it.fee, fee != 0 {
            return "每人約 \(money(fee))（粗估，沒核對過）"
        }
        return "還沒有資料"
    }

    var body: some View {
        DomySection(footer: "照片、招牌菜、平均消費、營業時間，要等接上地點查證才有。現在去之前請自己查一下。") {
            StopInfoRow(label: "為什麼排", text: whyText)
            StopInfoRow(label: "須知", text: tipText, unverified: hasTip, muted: !hasTip)
            StopInfoRow(label: "花費", text: feeText, muted: !hasFee)
        }
    }
}

/// 卡片裡的一列：上面小標，下面內容。須知是資料包的事實，一律標未核對
private struct StopInfoRow: View {
    let label: String
    let text: String
    var unverified: Bool = false
    var muted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
            HStack(spacing: T.Space.s2) {
                FieldLabel(label)
                if unverified {
                    Tag("未核對")
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

    var body: some View {
        if it.status == .pulled {
            VStack(alignment: .leading, spacing: T.Space.s4) {
                VisitNote(
                    say: it.say,
                    photos: it.photos ?? [],
                    onSay: { (say: String) -> Void in saveSay(say) },
                    onPhotos: { (next: [String]) -> Void in savePhotos(next) })
            }
        }
    }

    private func saveSay(_ say: String) {
        let stopId: String = id
        store.mutate { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            guard let x = findItem(trip, stopId) else { return }
            trip.slots[x.si].items[x.ii].say = say
            d.trip = trip
        }
    }

    private func savePhotos(_ next: [String]) {
        let stopId: String = id
        store.mutate { (d: inout AppState) -> Void in
            guard var trip = d.trip else { return }
            guard let x = findItem(trip, stopId) else { return }
            trip.slots[x.si].items[x.ii].photos = next
            d.trip = trip
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
                HStack(spacing: T.Space.s2) {
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

    var body: some View {
        if !it.kr.isEmpty {
            DomySection("別的找路方式", footer: "這一版只有韓文名稱，沒有門牌地址。接上地點查證後會帶出完整韓文地址。") {
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
                HStack(spacing: T.Space.s2) {
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
                DomySection(footer: "同一帶、差不多大小的三個。一站最多換三輪。") {
                    ForEach(alts, id: \.id) { (p: Place) in
                        DomyListRow(meta: meta(p), title: p.n) {
                            onPick(p)
                        }
                        .accessibilityIdentifier("stop-swap-\(p.id)")
                    }
                }
            } else {
                Card {
                    DomyText("這一帶沒有別的候選了。")
                }
            }
        }
        .presentationDetents([.medium, .large])
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
