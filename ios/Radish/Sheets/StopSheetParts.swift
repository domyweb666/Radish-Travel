// 一站的卡的每一面：主畫面、不去這一站、給司機看、移到別的時段、換一個。
// 對應 mobile/src/sheets/StopSheet.tsx 裡各個 mode 的畫面。由 StopSheet.swift 切換。
import SwiftUI
import UIKit

// MARK: - 主畫面

struct StopSheetMain: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Binding private var copied: Bool
    private let id: String
    private let it: Stop
    private let slot: Slot
    private let trip: Trip
    private let choices: [LearnChoice]
    private let setMode: (StopSheetMode) -> Void
    private let drop: (LearnChoice?) -> Void

    init(
        id: String,
        it: Stop,
        slot: Slot,
        trip: Trip,
        choices: [LearnChoice],
        copied: Binding<Bool>,
        setMode: @escaping (StopSheetMode) -> Void,
        drop: @escaping (LearnChoice?) -> Void
    ) {
        self.id = id
        self.it = it
        self.slot = slot
        self.trip = trip
        self.choices = choices
        self._copied = copied
        self.setMode = setMode
        self.drop = drop
    }

    private var st: Settings {
        tripSettings(store.s.settings, trip.tweaks)
    }

    /// 出發之後每一站都可以標成去過：不照順序走、忘記按、回來才補，都從這裡
    private var started: Bool {
        guard let phase = store.phase else { return false }
        switch phase {
        case .plan: return false
        case .trip: return true
        case .done: return true
        }
    }

    private var eats: Bool {
        it.c == .eat || it.c == .cafe
    }

    var body: some View {
        SheetScaffold(it.n, onClose: { sheets.close() }) {
            header
            whyCard
            infoCard
            allergyCard
            visitNote
            placeBlock
            actions
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: T.Space.s3) {
            CatIcon(it)
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(
                    "第 \(slot.day) 天\(PART[need: slot.part])・\(areaOf(it))・\(kindName(it))",
                    .subheadline, tone: .secondary)
                tags
            }
            .fillLeading()
        }
    }

    private var tags: some View {
        TagRow {
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

    private var whyCard: some View {
        Card(tone: .tint) {
            FieldLabel("為什麼排這一站")
            DomyText(it.why)
        }
    }

    private var feeText: String {
        if let fee = it.fee, fee != 0 {
            return "約 \(money(fee))（粗估，沒核對過）"
        }
        return "這一站還沒有花費資料。"
    }

    private var tipText: String {
        if let tip = it.tip, !tip.isEmpty {
            return "\(tip)。"
        }
        return "這一站還沒有須知。"
    }

    private var infoCard: some View {
        Card {
            FieldLabel("每人大概花多少")
            DomyText(feeText)
            FieldLabel("須知")
            DomyText(tipText)
            DomyText(
                "照片、招牌菜、平均消費、營業時間，要等接上地點查證才有。現在去之前請自己查一下。",
                .footnote, tone: .secondary)
        }
    }

    @ViewBuilder
    private var allergyCard: some View {
        if eats && !st.allergy.isEmpty {
            Card {
                FieldLabel("你有過敏：\(st.allergy.joined(separator: "、"))")
                DomyText("這一站我不知道店裡用了哪些食材，沒辦法幫你排除。點餐前把告知卡拿給店員看，自己確認。")
                DomyButton("打開過敏告知卡", variant: .secondary, size: .compact) {
                    setMode(.allergy)
                }
                .accessibilityIdentifier("stop-allergy")
            }
        }
    }

    @ViewBuilder
    private var visitNote: some View {
        if it.status == .pulled {
            VisitNote(
                say: it.say,
                photos: it.photos ?? [],
                onSay: { (say: String) -> Void in saveSay(say) },
                onPhotos: { (next: [String]) -> Void in savePhotos(next) })
        }
    }

    @ViewBuilder
    private var placeBlock: some View {
        if !it.kr.isEmpty {
            krCard
            routeSection
        } else {
            Card {
                DomyText(
                    (it.mine == true ? "這是你自己加的，這一版還不知道它在哪。" : "這一站目前只排到「哪一帶、吃哪一種」，還沒有指定店家。")
                        + "接上地點查證後，會給店名、韓文地址和地圖連結。",
                    .subheadline, tone: .secondary)
            }
        }
    }

    private var krCard: some View {
        Card {
            FieldLabel("韓文名稱（給司機或路人看）")
            DomyText(it.kr, .title1)
            HStack(spacing: T.Space.s2) {
                DomyButton(copied ? "複製了" : "複製韓文", variant: .secondary, size: .compact) {
                    UIPasteboard.general.string = it.kr
                    copied = true
                }
                .accessibilityIdentifier("stop-copy")
                DomyButton("放大給司機看", variant: .secondary, size: .compact) {
                    setMode(.show)
                }
                .accessibilityIdentifier("stop-show")
            }
        }
    }

    private var routeSection: some View {
        DomySection("找路", footer: "這一版只有韓文名稱，沒有門牌地址。接上地點查證後會帶出完整韓文地址。") {
            SettingsRow("用 Naver 地圖找路", value: "當地最常用") { openNaver(it.kr) }
            SettingsRow("用 Google 地圖開") { openGoogle(it.kr) }
            SettingsRow("用 Apple 地圖開") { openApple(it.kr) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if it.status == .kept {
            VStack(spacing: T.Space.s2) {
                if started {
                    DomyButton("去過了，拔起來", fullWidth: true) {
                        setStatus(.pulled, "「\(it.n)」拔起來了。往下可以寫一句、加照片。")
                    }
                    .accessibilityIdentifier("stop-pull")
                }
                DomyButton("移到別的時段", variant: .secondary, fullWidth: true) {
                    setMode(.move)
                }
                .accessibilityIdentifier("stop-move")
                DomyButton("換一個", variant: .secondary, fullWidth: true) {
                    setMode(.swap)
                }
                .accessibilityIdentifier("stop-swap")
                removeButton
            }
        } else {
            DomyButton("按錯了，這站還沒去", variant: .plain, fullWidth: true) {
                setStatus(.kept, "「\(it.n)」改回還沒去。寫的那一句和照片都還在。")
            }
            .accessibilityIdentifier("stop-unpull")
        }
    }

    private var removeButton: some View {
        DomyButton(choices.isEmpty ? "這次不去，放到下次再來" : "不想去這一站", variant: .plain, fullWidth: true) {
            if choices.isEmpty {
                drop(nil)
            } else {
                setMode(.drop)
            }
        }
        .accessibilityIdentifier("stop-remove")
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

// MARK: - 不去這一站

struct StopSheetDrop: View {
    private let it: Stop
    private let choices: [LearnChoice]
    private let back: () -> Void
    private let drop: (LearnChoice?) -> Void

    init(
        it: Stop,
        choices: [LearnChoice],
        back: @escaping () -> Void,
        drop: @escaping (LearnChoice?) -> Void
    ) {
        self.it = it
        self.choices = choices
        self.back = back
        self.drop = drop
    }

    var body: some View {
        SheetScaffold("不去「\(it.n)」", onClose: back) {
            DomyText("是這次不想去，還是以後都不要排？")
            DomyButton("只是這次不想，放到下次再來", fullWidth: true) {
                drop(nil)
            }
            .accessibilityIdentifier("stop-drop-once")
            ForEach(choices, id: \.kind) { (c: LearnChoice) in
                DomyButton(
                    c.kind == .place ? "以後不排這一站" : "以後不排「\(c.n)」",
                    variant: .secondary, fullWidth: true
                ) {
                    drop(c)
                }
                .accessibilityIdentifier("stop-drop-\(c.kind.rawValue)")
            }
            DomyButton("算了，留著", variant: .plain, fullWidth: true, action: back)
                .accessibilityIdentifier("stop-drop-cancel")
            DomyText(
                "選「以後不排」的話，之後每一趟排行程、換一個的時候都會跳過；有引號的那一顆是整個類別都不排。記下來的在「我」→「從行程學到的」，隨時可以拿掉。",
                .footnote, tone: .secondary)
        }
    }
}

// MARK: - 給司機看

struct StopSheetShow: View {
    private let it: Stop
    private let back: () -> Void

    init(it: Stop, back: @escaping () -> Void) {
        self.it = it
        self.back = back
    }

    var body: some View {
        SheetScaffold("給司機看", onClose: back) {
            Card {
                VStack(spacing: T.Space.s3) {
                    DomyText(it.kr, .largeTitle, align: .center)
                    DomyText("여기로 가 주세요（請到這裡）", .subheadline, tone: .secondary, align: .center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, T.Space.s8)
            }
        }
    }
}

// MARK: - 移到別的時段

struct StopSheetMove: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Binding private var to: StopMoveTarget
    private let id: String
    private let it: Stop
    private let trip: Trip
    private let back: () -> Void

    init(id: String, it: Stop, trip: Trip, to: Binding<StopMoveTarget>, back: @escaping () -> Void) {
        self.id = id
        self.it = it
        self.trip = trip
        self._to = to
        self.back = back
    }

    private var days: [Int] {
        Array(stride(from: 1, through: trip.days, by: 1))
    }

    var body: some View {
        let ok: Bool = slotAt(trip, to.day, to.part) != nil
        let big: Int = bigCount(trip, to.day)
        let count: Int = dayStops(trip, to.day).count
        SheetScaffold("把「\(it.n)」移到", onClose: back) {
            FieldLabel("哪一天")
            dayChips
            FieldLabel("哪個時段")
            partChips
            DomyText("第 \(to.day) 天現在有 \(big) 個主要景點、共 \(count) 站。", .footnote, tone: .secondary)
            DomyButton("移過去", disabled: !ok, fullWidth: true) {
                move()
            }
            .accessibilityIdentifier("stop-move-go")
        }
    }

    private var dayChips: some View {
        ChipRow {
            ForEach(days, id: \.self) { (d: Int) in
                Chip("第 \(d) 天 \(fmtDay(addDays(trip.start, d - 1)))", selected: to.day == d) {
                    pickDay(d)
                }
                .accessibilityIdentifier("stop-move-day-\(d)")
            }
        }
    }

    private var partChips: some View {
        ChipRow {
            ForEach(PARTS, id: \.self) { (p: Part) in
                let free: Bool = slotAt(trip, to.day, p) != nil
                let name: String = PART[need: p]
                Chip(free ? name : "\(name)（在路上）", selected: to.part == p && free, disabled: !free) {
                    to = StopMoveTarget(day: to.day, part: p)
                }
                .accessibilityIdentifier("stop-move-part-\(p.rawValue)")
            }
        }
    }

    /// 換一天時，原本選的時段那天在路上，就改選那天第一個能排的時段
    private func pickDay(_ d: Int) {
        var part: Part = to.part
        if slotAt(trip, d, part) == nil {
            let firstFree: Part? = PARTS.first { (p: Part) -> Bool in slotAt(trip, d, p) != nil }
            part = firstFree ?? part
        }
        to = StopMoveTarget(day: d, part: part)
    }

    private func move() {
        let stopId: String = id
        let name: String = it.n
        let day: Int = to.day
        let part: Part = to.part
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = moveItem(&trip, stopId, day, part)
            d.trip = trip
            if let err { return err }
            if let warn = warnings(trip).first { return warn }
            return "「\(name)」移到第 \(day) 天\(PART[need: part])了。"
        }
        sheets.close()
    }
}

// MARK: - 換一個

struct StopSheetSwap: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    private let id: String
    private let it: Stop
    private let trip: Trip
    private let back: () -> Void

    init(id: String, it: Stop, trip: Trip, back: @escaping () -> Void) {
        self.id = id
        self.it = it
        self.trip = trip
        self.back = back
    }

    var body: some View {
        let alts: [Place] = alternatives(trip, store.s.settings, it)
        SheetScaffold("把「\(it.n)」換成", onClose: back) {
            if it.swaps >= 3 {
                Card {
                    DomyText("這一站已經換過三輪了。前面那幾個都合你的條件，挑一個就好。想要完全不同的，用講的跟我說。")
                }
            } else if !alts.isEmpty {
                DomySection(footer: "同一帶、差不多大小的三個。一站最多換三輪。") {
                    ForEach(alts, id: \.id) { (p: Place) in
                        DomyListRow(meta: meta(p), title: p.n) {
                            pick(p)
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

    private func pick(_ p: Place) {
        let stopId: String = id
        let name: String = it.n
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = replaceWith(&trip, stopId, p)
            d.trip = trip
            return err ?? "「\(name)」換成「\(p.n)」了。"
        }
        sheets.close()
    }
}
