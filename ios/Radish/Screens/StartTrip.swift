// 開一趟：基本資料一頁填完（TripForm），按「幫我排」。
// 第一趟在表單下面多問四題偏好（存進「我」），第二趟起照「平常的你」。
// 表單裡「想怎麼玩」可以不填（線框 New-Form）：有填就先照表單排好，再把那句當第一句問 AI（AppStore.talkWish）。
// 填到一半的放在 AppStore.startDraft，切分頁再回來還在。鍵盤出來時輸入框會被往上推，不會被蓋住。
// 對應 mobile/src/screens/StartTrip.tsx。
import SwiftUI

enum Lean: String, CaseIterable {
    case street, local, famous, mix
}

/// TS 的 { label, food }
private struct LeanInfo {
    let label: String
    let food: [FoodKind: Int]
}

private let LEAN: [Lean: LeanInfo] = [
    .street: LeanInfo(label: "市場和路邊小吃為主", food: [.street: 3, .local: 2, .famous: 0, .fine: 0]),
    .local: LeanInfo(label: "在地人常去的小館為主", food: [.street: 1, .local: 3, .famous: 1, .fine: 0]),
    .famous: LeanInfo(label: "排隊名店也想吃", food: [.street: 1, .local: 2, .famous: 3, .fine: 1]),
    .mix: LeanInfo(label: "都來一點", food: [.street: 2, .local: 2, .famous: 2, .fine: 1]),
]
private let LEANS: [Lean] = [.street, .local, .famous, .mix]

/// 第一趟多問的四題（TS 的 Prefs）。nil 是那一題還沒動過
struct StartPrefs {
    var purposes: [Purpose]?
    var pace: Pace?
    var lean: Lean?
    var likes: [Cat]?
}

/// 開一趟填到一半的，放在 AppStore
struct StartDraft {
    var form: TripFormValue = blankForm()
    var prefs: StartPrefs = StartPrefs()
    /// 這是不是第一趟（要不要問四題）。進這一頁時定住，中間去平常的我改東西也不會變
    var first: Bool?
    /// 選好的出發日放到過期了：哪一天。畫面上要講
    var expired: String?
}

/// 可以選好幾個：點了會亮，再點一次取消
private struct Multi<K: Hashable>: View {
    let options: [(K, String)]
    let value: [K]
    let onChange: ([K]) -> Void

    private func toggle(_ k: K) {
        if value.contains(k) {
            onChange(value.filter { (x: K) -> Bool in x != k })
        } else {
            onChange(value + [k])
        }
    }

    var body: some View {
        ChipRow {
            ForEach(options.indices, id: \.self) { (index: Int) in
                let option: (K, String) = options[index]
                Chip(option.1, selected: value.contains(option.0)) {
                    toggle(option.0)
                }
            }
        }
    }
}

/// 一題：小標在上，選項在下（TS 的 Group；SwiftUI 已經有 Group，所以改名）
private struct PrefGroup<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            FieldLabel(label)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StartTrip: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    @Environment(Sheets.self) private var sheets
    let goSettings: () -> Void

    init(goSettings: @escaping () -> Void) {
        self.goSettings = goSettings
    }

    private var form: TripFormValue {
        return store.startDraft.form
    }

    private var formBinding: Binding<TripFormValue> {
        return Binding<TripFormValue>(
            get: { store.startDraft.form },
            set: { (v: TripFormValue) in store.startDraft.form = v }
        )
    }

    private var first: Bool {
        return store.startDraft.first ?? !tuned
    }

    /// 進這一頁時定住是不是第一趟
    private func holdFirst() {
        if store.startDraft.first == nil {
            store.startDraft.first = !tuned
        }
    }

    /* 四題現在顯示的答案，按「幫我排」存的也是這一份。
       沒動過的：平常的我還沒設過就是一般的排法；填到一半跑去平常的我設了，就是那邊設的 */

    private var tuned: Bool {
        return store.s.settings.tuned
    }

    private var shownPurposes: [Purpose] {
        if let picked = store.startDraft.prefs.purposes { return picked }
        return tuned ? store.s.settings.purposes : []
    }

    private var shownPace: Pace {
        if let picked = store.startDraft.prefs.pace { return picked }
        return tuned ? store.s.settings.pace : Pace.mid
    }

    /// 平常的我設的吃法跟四種都對不上就是 nil，不動它
    private var shownLean: Lean? {
        if let picked = store.startDraft.prefs.lean { return picked }
        if !tuned { return Lean.local }
        let food: [FoodKind: Int] = store.s.settings.food
        return LEANS.first { (k: Lean) -> Bool in LEAN[need: k].food == food }
    }

    private var shownLikes: [Cat] {
        if let picked = store.startDraft.prefs.likes { return picked }
        if !tuned { return [] }
        let play: [Cat: Int] = store.s.settings.play
        return Cat.allCases.filter { (c: Cat) -> Bool in (play[c] ?? 0) > 0 }
    }

    private var missing: [String] {
        return missingOf(form)
    }

    /// 選好的出發日已經過了（選了今天，放過午夜才按）：不排，請他重選
    private func rejectPast(_ start: String) {
        Haptic.notify(.error)
        store.startDraft.form.start = nil
        store.startDraft.expired = start
        store.say("你選的 \(fmtDay(start))已經過了，行程還沒排。重選一次出發日。")
    }

    private func go() {
        // 先定住：下面會把 tuned 變成 true
        holdFirst()
        store.refreshToday()
        guard let start = form.start, !start.isEmpty,
            let days = form.days, days != 0,
            let arrive = form.arrive,
            let leave = form.leave,
            let people = form.people, people != 0
        else { return }
        if start < store.today {
            rejectPast(start)
            return
        }
        Haptic.notify(.success)
        let isFirst: Bool = first
        let wasTuned: Bool = tuned
        let purposes: [Purpose] = shownPurposes
        let pace: Pace = shownPace
        let lean: Lean? = shownLean
        let likes: [Cat] = shownLikes
        let filled: TripFormValue = form
        let wish: String? = cleanWish(filled.wish)
        // 沒寫 undoable，提示條不放「復原」；換了一趟，act 照樣會留一步。
        // 有寫那句的話，同一下還要升半頁，兩個動畫不要撞在一起
        store.act(animated: wish == nil) { (d: inout AppState) -> String? in
            if isFirst {
                var play: [Cat: Int] = [:]
                for k in likes {
                    play[k] = wasTuned ? (d.settings.play[k] ?? 1) : 1
                }
                d.settings.purposes = purposes
                d.settings.pace = pace
                if let lean { d.settings.food = LEAN[need: lean].food }
                d.settings.play = play
                d.settings.tuned = true
            }
            let draft: TripDraft = TripDraft(
                tweaks: filled.cleanTweaks, city: "seoul", base: filled.base,
                stayName: filled.cleanStayName, name: filled.cleanName, cover: filled.cover,
                start: start, days: days, arrive: arrive, leave: leave, people: people
            )
            var trip: Trip = generate(draft, d.settings)
            trip.planTweaks = draft.tweaks ?? []
            trip.wish = wish
            d.trip = trip
            d.chat = []
            var kept: [String: Bool] = [:]
            for (k, v) in d.checks where !k.hasPrefix("b_") {
                kept[k] = v
            }
            d.checks = kept
            d.settingsDirty = false
            d.debugDay = nil
            return "排好了。每一站下面那行，是為什麼排它。"
        }
        store.startDraft = StartDraft()
        // 行程已經有了，再問那句。送不送得出去都不影響行程
        if store.talkWish() {
            sheets.open(.reply)
        }
    }

    var body: some View {
        Screen("開一趟", actions: { TopActions() }) {
            VStack(alignment: .leading, spacing: T.Space.s5) {
                DomyText("填完按最下面的「幫我排」", .subheadline, tone: .secondary)
                // 還沒排也能先看須知：在當地、回程
                EntryChip("須知", icon: IconPaths.notes) {
                    nav.push(.notes)
                }
                .accessibilityIdentifier("open-notes")
                TripForm(
                    value: formBinding, minStart: store.today, fallbackBase: store.s.settings.base, showWish: true)
                if first {
                    firstCard
                } else {
                    DomyText("我照平常的你排：\(settingsSummary(store.s.settings))。", .subheadline, tone: .secondary)
                }
                actions
            }
        }
        // 清掉之後（開好了、匯入）也要重新定
        .onChange(of: store.startDraft.first == nil, initial: true) { (_: Bool, _: Bool) in
            holdFirst()
        }
    }

    private var firstCard: some View {
        Card {
            DomyText("第一次排，多問四題", .headline)
            DomyText(
                tuned
                    ? "沒選的照你在「平常的我」設的排。之後在那裡都能改。"
                    : "不選也可以，我先用一般的排法。之後在「平常的我」都能改。",
                .subheadline, tone: .secondary)
            purposeGroup
            paceGroup
            leanGroup
            likesGroup
        }
    }

    private var purposeGroup: some View {
        let options: [(Purpose, String)] = Purpose.allCases.map { (k: Purpose) -> (Purpose, String) in
            return (k, PURPOSE[need: k])
        }
        return PrefGroup("旅行回來，你希望怎樣？可以選好幾個") {
            Multi<Purpose>(options: options, value: shownPurposes) { (v: [Purpose]) in
                store.startDraft.prefs.purposes = v
            }
        }
    }

    private var paceGroup: some View {
        PrefGroup("一天想排多滿") {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                ForEach(PACES, id: \.self) { (k: Pace) in
                    let label: PaceLabel = PACE_TEXT[need: k]
                    VStack(alignment: .leading, spacing: T.Space.s1) {
                        Chip("\(label.name)：\(label.note)", selected: shownPace == k, onSurface: true) {
                            store.startDraft.prefs.pace = k
                        }
                        DomyText("例如：\(label.example)", .footnote, tone: .secondary)
                            .padding(.horizontal, T.Space.s2)
                    }
                }
            }
        }
    }

    private var leanGroup: some View {
        PrefGroup("吃的方面，比較偏哪一種") {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                ForEach(LEANS, id: \.self) { (k: Lean) in
                    Chip(LEAN[need: k].label, selected: shownLean == k, onSurface: true) {
                        store.startDraft.prefs.lean = k
                    }
                }
            }
        }
    }

    private var likesGroup: some View {
        let options: [(Cat, String)] = Cat.allCases.map { (k: Cat) -> (Cat, String) in
            return (k, CAT[need: k])
        }
        return PrefGroup("喜歡做什麼？可以選好幾個") {
            Multi<Cat>(options: options, value: shownLikes) { (v: [Cat]) in
                store.startDraft.prefs.likes = v
            }
        }
    }

    private var actions: some View {
        let lack: [String] = missing
        return VStack(spacing: T.Space.s2) {
            if let past = store.startDraft.expired, form.start == nil {
                DomyText("你選的 \(fmtDay(past))已經過了，行程還沒排。往上重選一次出發日。", .subheadline, tone: .destructive, align: .center)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("start-expired")
            }
            if !lack.isEmpty {
                DomyText("還沒填：\(lack.joined(separator: "、"))", .footnote, tone: .secondary, align: .center)
                    .frame(maxWidth: .infinity)
            }
            DomyButton("幫我排", disabled: !lack.isEmpty, fullWidth: true) {
                go()
            }
            .accessibilityIdentifier("start-go")
            if !first {
                DomyButton("我先去改平常的習慣", variant: .plain, fullWidth: true) {
                    goSettings()
                }
                .accessibilityIdentifier("start-settings")
            }
            undoButton
            backButton
        }
    }

    /// 剛不要的那一版、剛收進去過的旅行的那一趟：提示條過了，這裡還拿得回來
    @ViewBuilder
    private var undoButton: some View {
        if let trip = store.undoTrip {
            DomyButton(
                "復原，拿回「\(tripTitle(trip))・\(fmtDay(trip.start))出發」",
                variant: .plain,
                fullWidth: true
            ) {
                store.undo()
            }
            .accessibilityIdentifier("start-undo")
        }
    }

    /// 從「旅行」按開新的一趟進來的：原本那趟在「其他排好的」最上面，可以直接回去
    @ViewBuilder
    private var backButton: some View {
        if let back = store.s.shelf.first {
            let backId: String = back.id
            DomyButton(
                "不排了，回「\(tripTitle(back.trip))・\(fmtDay(back.trip.start))出發」",
                variant: .plain,
                fullWidth: true
            ) {
                store.act(undoable: true) { (d: inout AppState) -> String? in
                    return openShelved(&d, backId)
                }
            }
            .accessibilityIdentifier("start-back")
        }
    }
}
