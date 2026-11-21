// 「行前」分頁：照旅遊的時間線排，出發前 → 在當地 → 回程，最後一格是花費。
// 打開時停在哪一段，看這趟走到哪：還沒出發是「出發前」，旅途中是「在當地」，最後一天和回來之後是「回程」。
// 每一條只留一行短的核對狀態；完整的來源收在「看每一條的來源」。
// 對應 mobile/src/screens/PrepScreen.tsx。四段各一個檔：PrepBefore、PrepThere、PrepBack、PrepCost；這個檔放外框和共用的小元件。
import SwiftUI

/// 這趟走到哪，就先開哪一段
private func stageOf(_ phase: Phase?, _ days: Int) -> PrepStage {
    guard let phase else { return .before }
    switch phase {
    case .plan:
        return .before
    case .done:
        return .back
    case .trip(let day):
        return day >= days ? .back : .there
    }
}

/// 列上只放短的：二手核對・11/14，或是未核對
func prepFactShort(_ f: Fact) -> String {
    if f.checked.isEmpty { return "未核對" }
    let parts: [String] = f.checked.components(separatedBy: "-")
    guard parts.count >= 3, let m = Int(parts[1]), let d = Int(parts[2]) else {
        return "\(f.status)・\(f.checked)"
    }
    return "\(f.status)・\(m)/\(d)"
}

func prepFactFull(_ f: Fact) -> String {
    if f.checked.isEmpty { return "還沒核對過，沒有來源" }
    return "\(f.status) \(f.checked)・來源：\(f.source)"
}

/// 檢查表、地雷的每一條在 TS 都是 Fact 多幾欄；Swift 是不同的型別，要一起列來源時先轉成 Fact
func prepFact(_ r: CheckItem) -> Fact {
    return Fact(text: r.text, status: r.status, checked: r.checked, source: r.source)
}

func prepFact(_ r: TabooFact) -> Fact {
    return Fact(text: r.text, status: r.status, checked: r.checked, source: r.source)
}

/// TS 的 TextRow 碰到空字串的 note 不會畫；Swift 的 TextRow 只看是不是 nil，所以空的先轉成 nil
func prepNote(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
}

private struct PrepSources: View {
    let title: String
    let facts: [Fact]
    let onClose: () -> Void

    var body: some View {
        SheetScaffold(title, onClose: onClose) {
            DomyText(
                "「二手核對」是從旅遊媒體交叉對過，沒有直接讀官方頁。「來源較舊」是找到的資料比較舊，可能已經變了。「未核對」是還沒查。入境規定出發前請回官方頁再看一次。",
                .subheadline, tone: .secondary)
            DomySection {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    TextRow(f.text, note: prepNote(prepFactFull(f)))
                }
            }
        }
    }
}

/// 每一段最下面那顆「看每一條的來源」
struct PrepSourcesButton: View {
    let title: String
    let facts: [Fact]
    @State private var open: Bool = false

    init(title: String, facts: [Fact]) {
        self.title = title
        self.facts = facts
    }

    var body: some View {
        DomyButton("看每一條的來源", variant: .plain, fullWidth: true) {
            open = true
        }
        .accessibilityIdentifier("prep-sources")
        .sheet(isPresented: $open) {
            PrepSources(title: title, facts: facts) {
                open = false
            }
            .tint(C.accent)
        }
    }
}

struct PrepFactList: View {
    let title: String
    let facts: [Fact]
    var footer: String?

    init(title: String, facts: [Fact], footer: String? = nil) {
        self.title = title
        self.facts = facts
        self.footer = footer
    }

    var body: some View {
        DomySection(title, footer: footer) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, r in
                TextRow(r.text, note: prepNote(prepFactShort(r)))
            }
        }
    }
}

struct PrepPickList: View {
    let title: String
    let items: [Tip]
    var footer: String?

    init(title: String, items: [Tip], footer: String? = nil) {
        self.title = title
        self.items = items
        self.footer = footer
    }

    private func name(_ p: Tip) -> String {
        if let kr = p.kr, !kr.isEmpty {
            return "\(p.n)　\(kr)"
        }
        return p.n
    }

    var body: some View {
        DomySection(title, footer: footer) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, p in
                TextRow(name(p), note: prepNote(p.note))
            }
        }
    }
}

/// open：從別頁跳過來時指定要開哪一段。沒指定就照這趟走到哪
struct PrepScreen: View {
    @Environment(AppStore.self) private var store
    let open: PrepStage?
    let goTrip: () -> Void
    /// 現在開的那一段。nil 是還沒決定（畫面剛出來那一下），先照這趟走到哪
    @State private var picked: PrepStage?

    init(open: PrepStage?, goTrip: @escaping () -> Void) {
        self.open = open
        self.goTrip = goTrip
        self._picked = State(initialValue: open)
    }

    private var auto: PrepStage {
        return stageOf(store.phase, store.s.trip?.days ?? 0)
    }

    private var stage: PrepStage {
        return picked ?? auto
    }

    private let options: [(PrepStage, String)] = [
        (PrepStage.before, "出發前"),
        (PrepStage.there, "在當地"),
        (PrepStage.back, "回程"),
        (PrepStage.cost, "花費"),
    ]

    var body: some View {
        Screen("行前") {
            Segmented(value: stage, options: options) { (next: PrepStage) in
                picked = next
            }
            stageBody
        }
        .onAppear {
            // TS 是畫面出來時決定一次，之後不跟著日期變
            if picked == nil {
                picked = auto
            }
        }
        .onChange(of: open) { _, next in
            if let next {
                picked = next
            }
        }
    }

    @ViewBuilder private var stageBody: some View {
        switch stage {
        case .before:
            PrepBefore()
        case .there:
            PrepThere()
        case .back:
            PrepBack()
        case .cost:
            if store.s.trip != nil {
                PrepCost()
            } else {
                DomyEmptyState(
                    icon: IconPaths.tabTrip,
                    title: "還沒有行程",
                    message: "排好一趟之後，這裡會有每人大概要花多少。",
                    actionTitle: "去排一趟",
                    action: { goTrip() }
                )
            }
        }
    }
}
