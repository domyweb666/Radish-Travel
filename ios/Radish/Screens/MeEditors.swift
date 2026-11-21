// 「我」分頁裡點一列打開的那些卡：單選的、可以選好幾個的、從行程學到的、貼上備份、全部清掉。
// 對應 mobile/src/screens/MeScreen.tsx 裡的 PickSheet 和各張 Sheet。
import SwiftUI

/// 正在改哪一項。TS 的 Editing（'import' 在 Swift 是保留字，所以叫 importBackup，存的字不變）
enum MeEditing: String, Identifiable {
    case purposes, pace, wake, move, base, stay, budget, food, avoid, play, walk, body, learned
    case importBackup = "import"
    case reset

    var id: String { rawValue }
}

/// TS 的 Opt<V>：一個選項
struct MeOpt<V: Hashable> {
    let v: V
    let label: String
    let note: String?

    init(_ v: V, _ label: String, note: String? = nil) {
        self.v = v
        self.label = label
        self.note = note
    }
}

/// 各個單選項目的選項。TS 檔案最上面那幾個常數（PACE、WAKE、MOVE…）
enum MeOptions {
    static let pace: [MeOpt<Pace>] = PACES.map { (k: Pace) -> MeOpt<Pace> in
        let text: PaceLabel = PACE_TEXT[need: k]
        return MeOpt<Pace>(k, text.name, note: text.note)
    }

    static let paceExamples: String = {
        let lines: [String] = PACES.map { (k: Pace) -> String in
            let text: PaceLabel = PACE_TEXT[need: k]
            return "\(text.name)的一天：\(text.example)。"
        }
        return lines.joined(separator: "\n")
    }()

    static let wake: [MeOpt<Wake>] = [
        MeOpt<Wake>(Wake.early, "早起"),
        MeOpt<Wake>(Wake.normal, "普通"),
        MeOpt<Wake>(Wake.late, "睡到自然醒", note: "上午不排主要景點"),
    ]

    static let move: [MeOpt<Move>] = [
        MeOpt<Move>(Move.transit, "地鐵公車"),
        MeOpt<Move>(Move.taxi, "多搭計程車"),
        MeOpt<Move>(Move.walk, "能走就走"),
    ]

    static let walk: [MeOpt<Walk>] = WALKS.map { (k: Walk) -> MeOpt<Walk> in
        let text: LabelText = WALK_TEXT[need: k]
        return MeOpt<Walk>(k, text.name, note: text.note)
    }

    static let base: [MeOpt<BaseKey>] = BaseKey.allCases.map { (k: BaseKey) -> MeOpt<BaseKey> in
        return MeOpt<BaseKey>(k, HOTEL[need: k].n)
    }

    static let stays: [MeOpt<StayKind>] = StayKind.allCases.map { (k: StayKind) -> MeOpt<StayKind> in
        let text: StayText = STAY[need: k]
        return MeOpt<StayKind>(k, text.name, note: "一晚大約 \(money(text.perNight))，只拿來估花費")
    }

    static let budget: [MeOpt<Double>] = {
        let amounts: [Double] = [1000, 1500, 2500, 4000]
        return amounts.map { (b: Double) -> MeOpt<Double> in MeOpt<Double>(b, money(b)) }
    }()

    static func label<V: Hashable>(_ opts: [MeOpt<V>], _ v: V) -> String {
        let found: MeOpt<V>? = opts.first { (o: MeOpt<V>) -> Bool in o.v == v }
        return found?.label ?? ""
    }
}

/// 有就拿掉、沒有就加在最後面
private func toggled<V: Equatable>(_ list: [V], _ v: V) -> [V] {
    if list.contains(v) {
        return list.filter { (x: V) -> Bool in x != v }
    }
    return list + [v]
}

private func without(_ list: [String], _ v: String) -> [String] {
    return list.filter { (x: String) -> Bool in x != v }
}

/// 每張卡最下面那顆「好了」
private struct MeDoneButton: View {
    let action: () -> Void

    var body: some View {
        DomyButton("好了", fullWidth: true, action: action)
            .accessibilityIdentifier("me-done")
    }
}

/// 單選的一張卡：選了就關
struct MePickSheet<V: Hashable>: View {
    let title: String
    let options: [MeOpt<V>]
    let value: V
    let footer: String?
    let onPick: (V) -> Void
    let onClose: () -> Void

    init(
        _ title: String,
        options: [MeOpt<V>],
        value: V,
        footer: String? = nil,
        onPick: @escaping (V) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.options = options
        self.value = value
        self.footer = footer
        self.onPick = onPick
        self.onClose = onClose
    }

    var body: some View {
        SheetScaffold(title, onClose: onClose) {
            DomySection(footer: footer) {
                ForEach(Array(options.enumerated()), id: \.offset) { _, o in
                    DomyListRow(meta: o.note, title: o.label, selected: o.v == value) {
                        onPick(o.v)
                        onClose()
                    }
                }
            }
        }
    }
}

/// 照 MeScreen 說的那一項，顯示對應的卡
struct MeEditorSheet: View {
    @Environment(AppStore.self) private var store
    let kind: MeEditing
    @Binding var backup: String
    @Binding var importErr: String?
    let close: () -> Void

    init(kind: MeEditing, backup: Binding<String>, importErr: Binding<String?>, close: @escaping () -> Void) {
        self.kind = kind
        self._backup = backup
        self._importErr = importErr
        self.close = close
    }

    private var st: Settings { store.s.settings }

    var body: some View {
        switch kind {
        case .purposes:
            MePurposesSheet(close: close)
        case .food:
            MeFoodSheet(close: close)
        case .avoid:
            MeAvoidSheet(close: close)
        case .body:
            MeBodySheet(close: close)
        case .learned:
            MeLearnedSheet(close: close)
        case .play:
            MePlaySheet(wish: st.wish, close: close)
        case .importBackup:
            MeImportSheet(backup: $backup, importErr: $importErr, close: close)
        case .reset:
            MeResetSheet(close: close)
        case .pace, .wake, .walk, .move:
            habitPick
        case .base, .stay, .budget:
            moneyPick
        }
    }

    @ViewBuilder private var habitPick: some View {
        switch kind {
        case .pace:
            MePickSheet<Pace>(
                "一天排多滿", options: MeOptions.pace, value: st.pace, footer: MeOptions.paceExamples,
                onPick: { (v: Pace) in store.setSettings { (s: inout Settings) in s.pace = v } },
                onClose: close)
        case .wake:
            MePickSheet<Wake>(
                "早上", options: MeOptions.wake, value: st.wake,
                onPick: { (v: Wake) in store.setSettings { (s: inout Settings) in s.wake = v } },
                onClose: close)
        case .walk:
            MePickSheet<Walk>(
                "一天能走多少", options: MeOptions.walk, value: st.walk,
                footer: "站和站之間的距離是照直線估的；逛一個景點裡面要走多少，這裡算不到。",
                onPick: { (v: Walk) in store.setSettings { (s: inout Settings) in s.walk = v } },
                onClose: close)
        case .move:
            MePickSheet<Move>(
                "怎麼移動", options: MeOptions.move, value: st.move,
                onPick: { (v: Move) in store.setSettings { (s: inout Settings) in s.move = v } },
                onClose: close)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var moneyPick: some View {
        switch kind {
        case .base:
            MePickSheet<BaseKey>(
                "通常住哪一帶", options: MeOptions.base, value: st.base,
                onPick: { (v: BaseKey) in store.setSettings { (s: inout Settings) in s.base = v } },
                onClose: close)
        case .stay:
            MePickSheet<StayKind>(
                "住宿", options: MeOptions.stays, value: st.stay,
                onPick: { (v: StayKind) in store.setSettings { (s: inout Settings) in s.stay = v } },
                onClose: close)
        case .budget:
            MePickSheet<Double>(
                "一天吃喝（每人）", options: MeOptions.budget, value: st.budget,
                onPick: { (v: Double) in store.setSettings { (s: inout Settings) in s.budget = v } },
                onClose: close)
        default:
            EmptyView()
        }
    }
}

/* ---------- 旅行回來想怎樣 ---------- */

private struct MePurposesSheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    var body: some View {
        let picked: [Purpose] = store.s.settings.purposes
        SheetScaffold("旅行回來想怎樣", onClose: close) {
            DomyText("可以選好幾個，選到的那幾類會排得比較多。都不選就是都可以。", .subheadline, tone: .secondary)
            ChipRow {
                ForEach(Purpose.allCases, id: \.self) { (k: Purpose) in
                    Chip(PURPOSE[need: k], selected: picked.contains(k)) {
                        store.setSettings { (s: inout Settings) in
                            s.purposes = toggled(s.purposes, k)
                        }
                    }
                }
            }
            MeDoneButton(action: close)
        }
    }
}

/* ---------- 吃的偏好 ---------- */

private struct MeFoodSheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    private var nowText: String {
        let fp: [FoodKind: Int] = foodPct(store.s.settings)
        let kinds: [FoodKind] = FoodKind.allCases.filter { (k: FoodKind) -> Bool in (fp[k] ?? 0) != 0 }
        let parts: [String] = kinds.map { (k: FoodKind) -> String in
            return "\(FOOD[need: k].name) \(fp[k] ?? 0)%"
        }
        return "四種各自選多常吃，晚餐會照比例分。現在是：\(parts.joined(separator: "、"))。"
    }

    private var levels: [(Int, String)] {
        var out: [(Int, String)] = []
        for (index, name) in FLV.enumerated() {
            out.append((index, name))
        }
        return out
    }

    var body: some View {
        SheetScaffold("吃的偏好", onClose: close) {
            DomyText(nowText, .subheadline, tone: .secondary)
            ForEach(FoodKind.allCases, id: \.self) { (k: FoodKind) in
                kindBlock(k)
            }
            MeDoneButton(action: close)
        }
    }

    private func kindBlock(_ k: FoodKind) -> some View {
        let text: FoodText = FOOD[need: k]
        let level: Int = store.s.settings.food[k] ?? 0
        return VStack(alignment: .leading, spacing: T.Space.s2) {
            VStack(alignment: .leading, spacing: 0) {
                DomyText(text.name, .headline)
                DomyText(text.desc, .footnote, tone: .secondary)
            }
            Segmented(value: level, options: levels) { (v: Int) in
                store.setSettings { (s: inout Settings) in
                    s.food[k] = v
                }
            }
        }
    }
}

/* ---------- 過敏和不吃的 ---------- */

private struct MeAvoidSheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    private var st: Settings { store.s.settings }

    var body: some View {
        SheetScaffold("過敏和不吃的", onClose: close) {
            DomyText(
                "分三層，越上面越嚴。這一版吃的站只排到「哪一帶、吃哪一種」，還沒有指定店家，所以我沒辦法照這些幫你挑店。用講的改行程時，AI 會照這三層來。",
                .subheadline, tone: .secondary)
            allergyBlock
            AllergyCardView(list: st.allergy)
            avoidBlock
            mehBlock
            MeDoneButton(action: close)
        }
    }

    private var allergyBlock: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText("過敏，不能出錯", .headline)
            DomyText("有選的話，每個吃的站都會提醒你，還會給你一張韓文告知卡，點餐前拿給店員看。", .footnote, tone: .secondary)
            ChipRow {
                ForEach(ALLERGENS, id: \.n) { (a: Allergen) in
                    Chip(a.n, selected: st.allergy.contains(a.n)) {
                        store.setSettings { (s: inout Settings) in
                            s.allergy = toggled(s.allergy, a.n)
                        }
                    }
                }
            }
        }
    }

    private var avoidBlock: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText("絕對不吃", .headline)
            ChipRow {
                ForEach(AVOID, id: \.self) { (a: String) in
                    Chip(a, selected: st.avoid.contains(a)) {
                        store.setSettings { (s: inout Settings) in
                            s.avoid = toggled(s.avoid, a)
                            s.meh = without(s.meh, a)
                        }
                    }
                }
            }
        }
    }

    private var mehBlock: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyText("不愛，但同行的人想吃可以", .headline)
            ChipRow {
                ForEach(MEH, id: \.self) { (a: String) in
                    Chip(a, selected: st.meh.contains(a)) {
                        store.setSettings { (s: inout Settings) in
                            s.meh = toggled(s.meh, a)
                            s.avoid = without(s.avoid, a)
                        }
                    }
                }
            }
        }
    }
}

/* ---------- 身體上要避開的 ---------- */

private struct MeBodySheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    var body: some View {
        let picked: [BodyLimit] = store.s.settings.body
        SheetScaffold("身體上要避開的", onClose: close) {
            DomyText("可以選好幾個。有選的，排行程時會照下面寫的做。", .subheadline, tone: .secondary)
            ForEach(BODIES, id: \.self) { (k: BodyLimit) in
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    ChipRow {
                        Chip(BODY_TEXT[k] ?? "", selected: picked.contains(k)) {
                            store.setSettings { (s: inout Settings) in
                                s.body = toggled(s.body, k)
                            }
                        }
                    }
                    DomyText(BODY_NOTE[k] ?? "", .footnote, tone: .secondary)
                }
            }
            MeDoneButton(action: close)
        }
    }
}

/* ---------- 從行程學到的 ---------- */

private struct MeLearnedSheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    var body: some View {
        let learned: [Learned] = store.s.settings.learned
        SheetScaffold("從行程學到的", onClose: close) {
            if !learned.isEmpty {
                DomySection(footer: "拿掉之後，下一次排行程就會再排到它。拿掉可以復原。") {
                    ForEach(learned, id: \.id) { (l: Learned) in
                        learnedRow(l)
                    }
                }
            } else {
                Card {
                    DomyText("還沒有。在行程上點一站、按「不想去這一站」、選「以後不排」，這裡就會多一條。", .body)
                }
            }
            MeDoneButton(action: close)
        }
    }

    private func learnedRow(_ l: Learned) -> some View {
        let line: String = "以後\(learnedText(l))"
        return TextRow(line, note: l.source) {
            DomyButton("拿掉", variant: .plain, size: .compact, label: "拿掉：\(line)") {
                store.act(undoable: true) { (d: inout AppState) -> String? in
                    let gone: Learned? = unlearn(&d.settings, l.id)
                    return gone != nil ? "拿掉了：\(line)。" : nil
                }
            }
            .accessibilityIdentifier("me-unlearn-\(l.id)")
        }
    }
}

/* ---------- 喜歡做什麼 ---------- */

private struct MePlaySheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void
    @State private var wish: String

    private static let wishMax: Int = 80

    init(wish: String, close: @escaping () -> Void) {
        self.close = close
        self._wish = State(initialValue: wish)
    }

    private var st: Settings { store.s.settings }

    var body: some View {
        SheetScaffold("喜歡做什麼", onClose: close) {
            DomyText("點一下是喜歡，再點一下是最愛，再點取消。都不選就是都可以。", .subheadline, tone: .secondary)
            catChips
            FieldLabel("更細的")
            tagChips
            wishField
            DomyText(
                "「更細的」和「其他想做的」這一版先記著，還不會照它排。接上 AI 之後，排行程和用講的改都會看這兩項。",
                .footnote, tone: .secondary)
            MeDoneButton {
                commitWish()
                close()
            }
        }
    }

    private var catChips: some View {
        ChipRow {
            ForEach(Cat.allCases, id: \.self) { (k: Cat) in
                let v: Int = st.play[k] ?? 0
                Chip(v == 2 ? "\(CAT[need: k])・最愛" : CAT[need: k], selected: v > 0) {
                    store.setSettings { (s: inout Settings) in
                        if v == 0 {
                            s.play[k] = 1
                        } else if v == 1 {
                            s.play[k] = 2
                        } else {
                            s.play.removeValue(forKey: k)
                        }
                    }
                }
            }
        }
    }

    private var tagChips: some View {
        ChipRow {
            ForEach(INTEREST_TAGS, id: \.self) { (t: String) in
                Chip(t, selected: st.tags.contains(t)) {
                    store.setSettings { (s: inout Settings) in
                        s.tags = toggled(s.tags, t)
                    }
                }
            }
        }
    }

    // TS 是輸入框離開時存。這裡按鍵盤的完成、按「好了」、關掉這張卡的時候都存一次，打的字才不會不見
    private var wishField: some View {
        DomyTextField(
            "其他想做的",
            text: $wish,
            placeholder: "想到什麼寫什麼",
            helper: "上面沒有的，自己寫。例如：想去看棒球、想找二手唱片行。",
            onSubmit: { commitWish() }
        )
        .onChange(of: wish) { _, new in
            if new.count > MePlaySheet.wishMax {
                wish = String(new.prefix(MePlaySheet.wishMax))
            }
        }
        .onDisappear { commitWish() }
    }

    private func commitWish() {
        let v: String = wish.trimmingCharacters(in: .whitespacesAndNewlines)
        if v == store.s.settings.wish { return }
        store.setSettings { (s: inout Settings) in
            s.wish = v
        }
    }
}

/* ---------- 貼上備份 ---------- */

/// TS 的 !!JSON.parse(backup).settings：是一包東西，而且裡面有 settings
private func hasSettings(_ raw: String) -> Bool {
    guard let data = raw.data(using: .utf8) else { return false }
    guard let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
        return false
    }
    guard let object = parsed as? [String: Any], let value = object["settings"] else { return false }
    if value is NSNull { return false }
    if let text = value as? String { return !text.isEmpty }
    if let number = value as? NSNumber { return number.doubleValue != 0 }
    return true
}

private struct MeImportSheet: View {
    @Environment(AppStore.self) private var store
    @Binding var backup: String
    @Binding var importErr: String?
    let close: () -> Void

    var body: some View {
        SheetScaffold("貼上備份", onClose: close) {
            DomyTextField(
                "備份內容",
                text: $backup,
                helper: "把之前複製的備份整段貼進來。現在手機裡的資料會被換掉。",
                error: importErr,
                multiline: true
            )
            .lineLimit(6...)  // domy-ignore: 輸入框至少留幾行，對應 TS 的 minHeight
            .onChange(of: backup) { _, _ in
                importErr = nil
            }
            DomyButton("還原", fullWidth: true) {
                restore()
            }
            .accessibilityIdentifier("me-import-go")
        }
    }

    private func restore() {
        var next: AppState?
        if hasSettings(backup), let data = backup.data(using: .utf8) {
            next = AppState.hydrate(data)
        }
        guard let state = next else {
            importErr = "這段不是蘿蔔旅行的備份。請回備忘錄把整段重新複製一次。"
            return
        }
        store.replaceAll(state)
        backup = ""
        close()
        store.say("還原好了。")
    }
}

/* ---------- 全部清掉 ---------- */

private struct MeResetSheet: View {
    @Environment(AppStore.self) private var store
    let close: () -> Void

    var body: some View {
        SheetScaffold("全部清掉？", onClose: close) {
            DomyText("所有的旅行、下次再來、設定都會回到一開始的樣子，救不回來。想留著的話，先回上一頁按「複製備份」。", .body)
            DomyButton("清掉", variant: .destructive, fullWidth: true) {
                store.replaceAll(AppState())
                close()
                store.say("全部清掉了。")
            }
            .accessibilityIdentifier("me-reset-confirm")
            DomyButton("不清了", variant: .secondary, fullWidth: true) {
                close()
            }
            .accessibilityIdentifier("me-reset-cancel")
        }
    }
}
