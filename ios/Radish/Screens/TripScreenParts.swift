// 「這趟」分頁裡的幾塊：每天的分頁、一站的列、一天的行程卡、旅途中的「下一站」。
// 對應 mobile/src/screens/TripScreen.tsx 裡的 DayTabs、StopRow、DayCard、NextStop。
import SwiftUI

/// 每一天一個分頁，橫向排，天數多可以左右滑
struct TripDayTabs: View {
    let trip: Trip
    let value: Int
    let today: Int?
    let onChange: (Int) -> Void

    var body: some View {
        let days: [Int] = Array(1...max(1, trip.days))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: T.Space.s2) {
                ForEach(days, id: \.self) { (d: Int) in
                    tab(d)
                }
            }
            .padding(.horizontal, T.Size.screenMargin)
        }
        .padding(.horizontal, -T.Size.screenMargin)
    }

    private func tab(_ d: Int) -> some View {
        let on: Bool = d == value
        let isToday: Bool = d == today
        let date: String = fmtDay(addDays(trip.start, d - 1))
        let label: String = "第 \(d) 天，\(date)" + (isToday ? "，今天" : "")
        return Button {
            onChange(d)
        } label: {
            VStack(spacing: 0) {
                DomyText(isToday ? "今天" : "第 \(d) 天", .callout, tone: on ? .onAccent : .primary)
                DomyText(date, .caption, tone: on ? .onAccent : .secondary)
            }
            .padding(.horizontal, T.Space.s4)
            .frame(minHeight: T.Size.row)
            .background(
                on ? C.accent : C.surface,
                in: RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("day-tab-\(d)")
    }
}

/// 去過的站，名稱劃掉、變淡。列上不放蘿蔔
struct TripStopRow: View {
    let it: Stop
    let slot: Slot
    let action: () -> Void

    var body: some View {
        let part: String = PART[need: slot.part]
        return Button(action: action) {
            HStack(spacing: T.Space.s3) {
                CatIcon(it)
                texts(part)
            }
            .padding(.vertical, T.Space.s3)
            .padding(.horizontal, T.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(part)，\(it.n)，\(it.why)")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stop-row-\(it.id)")
    }

    private func texts(_ part: String) -> some View {
        let pulled: Bool = it.status == .pulled
        let booking: Bool = it.b == true
        let fromAI: Bool = it.ai == true
        return VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
            DomyText("\(part)・\(areaOf(it))", .footnote, tone: .secondary)
            DomyText(it.n, .headline, tone: pulled ? .secondary : .primary)
                .strikethrough(pulled)
            DomyText(it.why, .subheadline, tone: .strong)
            if booking || fromAI {
                TagRow {
                    if booking {
                        Tag("要先訂", tone: .accent)
                    }
                    if fromAI {
                        Tag("AI 加的・未核對", tone: .warn)
                    }
                }
            }
        }
        .fillLeading()
    }
}

/// 行程卡裡的一列
enum TripDayRow: Identifiable {
    case off(title: String)
    case leg(at: Int, text: String)
    case stop(it: Stop, slot: Slot)
    case blank(part: Part)

    var id: String {
        switch self {
        case .off: return "off"
        case .leg(let at, _): return "leg\(at)"
        case .stop(let it, _): return it.id
        case .blank(let part): return part.rawValue
        }
    }
}

/// 一天的行程要排成哪幾列。stops 是這天有幾站，total 是路上大約幾分鐘
func tripDayRows(_ trip: Trip, _ settings: Settings, _ day: Int) -> (rows: [TripDayRow], stops: Int, total: Int) {
    let slots: [Slot] = trip.slots.filter { (x: Slot) -> Bool in x.day == day }
    let stops: [Found] = dayStops(trip, day)
    let legs: [Leg?] = dayLegs(trip, settings, day)
    var total: Int = 0
    for l in legs {
        if let l { total += l.min }
    }
    // 站與站之間那一行：怎麼去、大概多久。第一站前面那段是從住的地方出發
    func legRow(_ i: Int, _ lead: String) -> TripDayRow {
        let l: Leg? = i < legs.count ? legs[i] : nil
        var text: String = "這一段距離不明，到時候查地圖"
        if let l {
            text = "\(l.mode)・\(l.min) 分鐘（估）"
        }
        return TripDayRow.leg(at: i, text: lead + text)
    }
    var rows: [TripDayRow] = []
    var off: [String] = []
    for sl in slots where sl.off == true {
        off.append(PART[need: sl.part])
    }
    if !off.isEmpty {
        rows.append(TripDayRow.off(title: "\(off.joined(separator: "、"))在路上"))
    }
    for sl in slots {
        if sl.off == true { continue }
        for it in sl.items {
            let at: Int? = stops.firstIndex { (x: Found) -> Bool in x.it.id == it.id }
            if let at {
                rows.append(legRow(at, at == 0 ? "從住的地方出發・" : ""))
            }
            rows.append(TripDayRow.stop(it: it, slot: sl))
        }
        if sl.items.isEmpty {
            rows.append(TripDayRow.blank(part: sl.part))
        }
    }
    if !stops.isEmpty {
        rows.append(legRow(stops.count, "回住的地方・"))
    }
    return (rows: rows, stops: stops.count, total: total)
}

/// frames：這天每一站的位置都記在裡面，操作說明要照亮第一站
struct TripDayCard: View {
    let trip: Trip
    let day: Int
    let frames: SpotFrames

    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets

    var body: some View {
        let plan: (rows: [TripDayRow], stops: Int, total: Int) = tripDayRows(trip, store.s.settings, day)
        let footer: String? =
            plan.stops > 0
            ? "\(plan.stops) 站・路上大約 \(plan.total) 分鐘（估）。點一站看韓文名稱、花費、怎麼去，也可以移走或換掉。"
            : nil
        return VStack(alignment: .leading, spacing: T.Space.s3) {
            DomySection(footer: footer) {
                ForEach(plan.rows) { (row: TripDayRow) in
                    rowView(row)
                }
            }
            if plan.stops > 0 {
                DomyButton("看這天的地圖", variant: .secondary, fullWidth: true) {
                    sheets.open(.map(day: day))
                }
                .accessibilityIdentifier("open-map")
            }
        }
    }

    @ViewBuilder
    private func rowView(_ row: TripDayRow) -> some View {
        switch row {
        case .off(let title):
            TextRow(title, note: "這段時間不排東西")
        case .leg(_, let text):
            DomyText(text, .footnote, tone: .secondary)
                .padding(.vertical, T.Space.s2)
        case .stop(let it, let slot):
            TripStopRow(it: it, slot: slot) {
                sheets.open(.stop(id: it.id))
            }
            .spotTarget("stop-row-\(it.id)", in: frames)
        case .blank(let part):
            TextRow("\(PART[need: part])・留白", note: "這段故意不排")
        }
    }
}

/// 剛拔起來的那一站
private struct PulledStop: Identifiable {
    let id: UUID = UUID()
    let name: String
    let size: StopSize
    let line: String
}

struct TripNextStop: View {
    let trip: Trip
    let day: Int

    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    // 剛拔起來的那一站。有值的時候整個畫面是拔蘿蔔的那一下
    @State private var pulled: PulledStop? = nil

    var body: some View {
        let all: [Found] = dayStops(trip, day)
        let left: [Found] = all.filter { (x: Found) -> Bool in x.it.status == .kept }
        return Card {
            if let next = left.first {
                nextStop(next.it, next.s)
            } else {
                DomyText("今天的都拔完了", .title2)
                DomyText("剩下的時間是你的。", .body, tone: .secondary)
            }
        }
        .fullScreenCover(item: $pulled) { (p: PulledStop) in
            PullMoment(name: p.name, size: p.size, line: p.line) {
                setPulled(nil)
            }
            .presentationBackground(Color.clear)
        }
    }

    /// 拔蘿蔔那一下自己淡入淡出，所以開和關都不要系統的滑入動畫
    private func setPulled(_ next: PulledStop?) {
        var quiet: Transaction = Transaction()
        quiet.disablesAnimations = true
        withTransaction(quiet) {
            pulled = next
        }
    }

    @ViewBuilder
    private func nextStop(_ it: Stop, _ slot: Slot) -> some View {
        DomyText("下一站・\(PART[need: slot.part])・\(areaOf(it))", .footnote, tone: .secondary)
        HStack(spacing: T.Space.s3) {
            CatIcon(it)
            VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
                DomyText(it.n, .title2)
                if !it.kr.isEmpty {
                    DomyText(it.kr, .subheadline, tone: .secondary)
                }
            }
            .fillLeading()
            Radish(size: it.s, scale: 1.4)
        }
        if let tip = it.tip, !tip.isEmpty {
            DomyText("\(tip)。", .subheadline, tone: .secondary)
        }
        DomyButton("去過了，拔起來", fullWidth: true, haptic: false) {
            pull(it)
        }
        .accessibilityIdentifier("next-pull")
        HStack(spacing: T.Space.s2) {
            DomyButton("地圖與韓文", variant: .secondary, size: .compact) {
                sheets.open(.stop(id: it.id))
            }
            .accessibilityIdentifier("next-detail")
            DomyButton("這站不去", variant: .secondary, size: .compact) {
                skip(it)
            }
            .accessibilityIdentifier("next-skip")
        }
    }

    private func pull(_ it: Stop) {
        let id: String = it.id
        let name: String = it.n
        let line: String = PULL_LINES.randomElement() ?? ""
        setPulled(PulledStop(name: name, size: it.s, line: line))
        store.act(undoable: true, animated: false) { (d: inout AppState) -> String? in
            if var trip = d.trip, let x = findItem(trip, id) {
                trip.slots[x.si].items[x.ii].status = .pulled
                d.trip = trip
            }
            return "「\(name)」拔起來了。點那一站可以寫一句、加照片。"
        }
    }

    private func skip(_ it: Stop) {
        let id: String = it.id
        let name: String = it.n
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            var seeds: [Seed] = d.seeds
            _ = seedOut(&trip, &seeds, id, "旅途中說不去了")
            d.trip = trip
            d.seeds = seeds
            return "「\(name)」放到下次再來了。"
        }
    }
}
