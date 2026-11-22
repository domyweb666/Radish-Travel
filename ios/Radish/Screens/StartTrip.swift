// 開一趟：基本資料一頁填完（TripForm），按「幫我排」。
// 第一趟在表單下面多問四題偏好（存進「我」），第二趟起照「平常的你」。
// 鍵盤出來時輸入框會被往上推，不會被蓋住。
// 對應 mobile/src/screens/StartTrip.tsx。
import SwiftUI

private enum Lean: String, CaseIterable {
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

/// 第一趟多問的四題（TS 的 Prefs）
private struct StartPrefs {
    var purposes: [Purpose] = []
    var pace: Pace = .mid
    var lean: Lean = .local
    var likes: [Cat] = []
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
    let goSettings: () -> Void
    @State private var form: TripFormValue = blankForm()
    @State private var prefs: StartPrefs = StartPrefs()

    init(goSettings: @escaping () -> Void) {
        self.goSettings = goSettings
    }

    private var first: Bool {
        return !store.s.settings.tuned
    }

    private var missing: [String] {
        return missingOf(form)
    }

    private func go() {
        Haptic.notify(.success)
        guard let start = form.start, !start.isEmpty,
            let days = form.days, days != 0,
            let arrive = form.arrive,
            let leave = form.leave,
            let people = form.people, people != 0
        else { return }
        let isFirst: Bool = first
        let picked: StartPrefs = prefs
        let filled: TripFormValue = form
        store.act { (d: inout AppState) -> String? in
            if isFirst {
                var play: [Cat: Int] = [:]
                for k in picked.likes {
                    play[k] = 1
                }
                d.settings.purposes = picked.purposes
                d.settings.pace = picked.pace
                d.settings.food = LEAN[need: picked.lean].food
                d.settings.play = play
                d.settings.tuned = true
            }
            let draft: TripDraft = TripDraft(
                tweaks: filled.cleanTweaks, city: "seoul", base: filled.base,
                stayName: filled.cleanStayName, name: filled.cleanName, cover: filled.cover,
                start: start, days: days, arrive: arrive, leave: leave, people: people
            )
            d.trip = generate(draft, d.settings)
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
    }

    var body: some View {
        Screen("開一趟", actions: { TopActions() }) {
            VStack(alignment: .leading, spacing: T.Space.s5) {
                DomyText("填好這一頁，我把整趟排好。排完想改，用講的就可以；這一頁之後也能回來改。", .subheadline, tone: .secondary)
                // 還沒排也能先看須知：在當地、回程
                EntryChip("須知", icon: IconPaths.notes) {
                    nav.push(.notes)
                }
                .accessibilityIdentifier("open-notes")
                TripForm(value: $form, minStart: store.today, fallbackBase: store.s.settings.base)
                if first {
                    firstCard
                } else {
                    DomyText("我照平常的你排：\(settingsSummary(store.s.settings))。", .subheadline, tone: .secondary)
                }
                actions
            }
        }
    }

    private var firstCard: some View {
        Card {
            DomyText("第一次排，多問四題", .headline)
            DomyText("不選也可以，我先用一般的排法。之後在「平常的我」都能改。", .subheadline, tone: .secondary)
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
            Multi<Purpose>(options: options, value: prefs.purposes) { (v: [Purpose]) in
                prefs.purposes = v
            }
        }
    }

    private var paceGroup: some View {
        PrefGroup("一天想排多滿") {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                ForEach(PACES, id: \.self) { (k: Pace) in
                    let label: PaceLabel = PACE_TEXT[need: k]
                    VStack(alignment: .leading, spacing: T.Space.s1) {
                        Chip("\(label.name)：\(label.note)", selected: prefs.pace == k, onSurface: true) {
                            prefs.pace = k
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
                    Chip(LEAN[need: k].label, selected: prefs.lean == k, onSurface: true) {
                        prefs.lean = k
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
            Multi<Cat>(options: options, value: prefs.likes) { (v: [Cat]) in
                prefs.likes = v
            }
        }
    }

    private var actions: some View {
        let lack: [String] = missing
        return VStack(spacing: T.Space.s2) {
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
            backButton
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
                store.act { (d: inout AppState) -> String? in
                    return openShelved(&d, backId)
                }
            }
            .accessibilityIdentifier("start-back")
        }
    }
}
