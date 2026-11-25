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
            .padding(.vertical, T.Space.s2)
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
    /// 那天去不了（休館、歇業）。去得了是 nil。核對過的不用加標籤
    var shut: StopShut? = nil
    /// 排的那個時段不開。開、或那天整天不開是 nil
    var partShut: String? = nil
    /// 那天要注意、但不算不開的。沒有、或上面的下一站卡講過了是 nil
    var caution: String? = nil
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
        .accessibilityLabel(spoken(part))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stop-row-\(it.id)")
    }

    /// 念給 VoiceOver 的：劃掉和小標籤看得到的，也要念得到
    private func spoken(_ part: String) -> String {
        var out: [String] = [part, it.n]
        if it.status == .pulled {
            out.append("去過了")
        }
        if let shut {
            out.append(shut.gone ? shut.why : closedLabel)
        }
        if let partShut {
            out.append(partShut)
        }
        if let caution {
            out.append("這天要注意：\(caution)")
        }
        if needsBook(it) {
            out.append("要先訂")
        }
        if it.ai == true {
            out.append("AI 加的・未核對")
        }
        if !it.why.isEmpty {
            out.append(it.why)
        }
        return out.joined(separator: "，")
    }

    /// 那天不開的小標籤
    private var closedLabel: String {
        return "這天\(kindWords(it.c).shut)"
    }

    private func texts(_ part: String) -> some View {
        let pulled: Bool = it.status == .pulled
        let booking: Bool = needsBook(it)
        let fromAI: Bool = it.ai == true
        let closed: Bool = shut?.gone == false
        return VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
            DomyText("\(part)・\(areaOf(it))", .footnote, tone: .secondary)
            DomyText(it.n, .headline, tone: pulled ? .secondary : .primary)
                .strikethrough(pulled)
            DomyText(it.why, .subheadline, tone: .strong)
            warns
            if closed || booking || fromAI {
                TagRow {
                    if closed {
                        Tag(closedLabel, tone: .warn)
                    }
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

    /// 去不了的原因，或這個時段不開、那天要注意的
    @ViewBuilder
    private var warns: some View {
        if let shut, shut.gone {
            WarnTag(shut.why)
        } else if partShut != nil || caution != nil {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                if let partShut {
                    WarnTag(partShut)
                }
                if let caution {
                    WarnTag("這天要注意：\(caution)")
                }
            }
        }
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
    @Environment(Nav.self) private var nav

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
            stopRow(it, slot)
        case .blank(let part):
            TextRow("\(PART[need: part])・留白", note: "這段故意不排")
        }
    }

    /// 下一站卡上的那一站，時段不開和要注意的卡上寫了，這一列不再講一次
    private func stopRow(_ it: Stop, _ slot: Slot) -> some View {
        let told: Bool = toldOnNext(trip, slot.day, store.phase) == it.id
        return TripStopRow(
            it: it, slot: slot, shut: stopShut(trip, it, slot.day, store.phase),
            partShut: told ? nil : stopPartShut(trip, it, slot, store.phase),
            caution: told ? nil : stopCaution(trip, it, slot.day, store.phase)
        ) {
            nav.push(.stop(id: it.id))
        }
        .spotTarget("stop-row-\(it.id)", in: frames)
    }
}

/// 剛拔起來的那一站
private struct PulledStop: Identifiable {
    let id: UUID = UUID()
    let name: String
    let size: StopSize
    let line: String
}

/// 這一天整天都在路上，沒有能排的時段
func dayOnRoad(_ trip: Trip, _ day: Int) -> Bool {
    return PARTS.allSatisfy { (p: Part) -> Bool in slotAt(trip, day, p) == nil }
}

/// 旅途中的下一站卡（線框 A2）。「這站不去」在卡的右上角，跟「去過了，拔起來」拉開（02-流程 9-1）；
/// 點站名進一站；中間是找路、給司機看，最下面是拔起來。卡外面是之後那一站和附近還有什麼
struct TripNextStop: View {
    let trip: Trip
    let day: Int

    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    // 剛拔起來的那一站。有值的時候整個畫面是拔蘿蔔的那一下
    @State private var pulled: PulledStop? = nil
    /// 給司機看的那一站。有值的時候是全螢幕的韓文名稱
    @State private var driver: Stop? = nil

    var body: some View {
        let all: [Found] = dayStops(trip, day)
        let left: [Found] = all.filter { (x: Found) -> Bool in x.it.status == .kept }
        return VStack(alignment: .leading, spacing: T.Space.s3) {
            Card {
                if let next = left.first {
                    nextStop(next, all)
                } else if all.isEmpty && dayOnRoad(trip, day) {
                    DomyText("今天都在路上", .title2)
                    DomyText("抵達前、離開後的時段不排東西。", .body, tone: .secondary)
                } else if all.isEmpty {
                    // 一站都沒排，沒有東西可以拔，不能說都拔完了
                    DomyText("今天沒有排站", .title2)
                    DomyText("時間是你的。想找地方，看看下面「附近還有什麼」。", .body, tone: .secondary)
                } else {
                    DomyText("今天的都拔完了", .title2)
                    DomyText("剩下的時間是你的。", .body, tone: .secondary)
                }
            }
            .fullScreenCover(item: $driver) { (it: Stop) in
                DriverView(name: it.n, kr: it.kr, addr: factOf(it.id)?.addr)
            }
            if left.count > 1 {
                afterRow(left[1])
            }
            DomyButton("附近還有什麼", variant: .secondary, size: .compact) {
                sheets.open(.nearby(day: day))
            }
            .accessibilityIdentifier("next-nearby")
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
    private func nextStop(_ next: Found, _ all: [Found]) -> some View {
        let it: Stop = next.it
        HStack(alignment: .center, spacing: T.Space.s2) {
            DomyText("下一站・\(PART[need: next.s.part])・\(areaOf(it))", .footnote, tone: .secondary)
                .fillLeading()
            Button {
                skip(it)
            } label: {
                DomyText("這站不去", .subheadline, tone: .strong, lines: 1)
                    .frame(minHeight: T.Size.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            // 只縮按鈕的高度：左邊字放大、換行的時候，上下才不會貼到卡邊和站名
            .padding(.vertical, -T.Space.s2)
            .accessibilityIdentifier("next-skip")
        }
        titleButton(it)
        warns(next)
        DomyText(legText(next, all), .subheadline, tone: .secondary)
        if !it.kr.isEmpty {
            // 字級放大時兩顆放不下，改成一顆一列
            PairLayout(spacing: T.Space.s2) {
                DomyButton("用 Naver 找路", variant: .secondary, size: .compact, fullWidth: true) {
                    openNaver(it.kr)
                }
                .accessibilityIdentifier("next-naver")
                DomyButton("給司機看", variant: .secondary, size: .compact, fullWidth: true) {
                    driver = it
                }
                .accessibilityIdentifier("next-driver")
            }
        }
        DomyButton("去過了，拔起來", fullWidth: true, haptic: false) {
            pull(it)
        }
        .accessibilityIdentifier("next-pull")
    }

    /// 今天去不了的原因；去得了的話，排的時段不開、今天要注意的，各一行疊在一起
    @ViewBuilder
    private func warns(_ next: Found) -> some View {
        let it: Stop = next.it
        let partShut: String? = stopPartShut(trip, it, next.s, store.phase)
        let caution: String? = stopCaution(trip, it, next.s.day, store.phase)
        if let shut = stopShut(trip, it, next.s.day, store.phase) {
            WarnTag(shut.gone ? shut.why : "今天\(kindWords(it.c).shut)：\(shut.why)")
                .accessibilityIdentifier("next-closed")
        } else if partShut != nil || caution != nil {
            VStack(alignment: .leading, spacing: T.Space.s1) {
                if let partShut {
                    WarnTag(partShut)
                        .accessibilityIdentifier("next-part-closed")
                }
                if let caution {
                    WarnTag("今天要注意：\(caution)")
                        .accessibilityIdentifier("next-caution")
                }
            }
        }
    }

    /// 站名那一塊，點了進一站（S06）
    private func titleButton(_ it: Stop) -> some View {
        Button {
            nav.push(.stop(id: it.id))
        } label: {
            HStack(spacing: T.Space.s3) {
                CatIcon(it)
                VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
                    DomyText(it.n, .title2)
                    if !it.kr.isEmpty {
                        DomyText(it.kr, .subheadline, tone: .secondary)
                    }
                }
                .fillLeading()
                Chevron()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("下一站，\(it.n)，看這一站")
        .accessibilityIdentifier("next-detail")
    }

    /// 從上一站（第一站是從住的地方）過來怎麼去、大概多久。手機算的，一律帶（估）
    private func legText(_ next: Found, _ all: [Found]) -> String {
        let legs: [Leg?] = dayLegs(trip, store.s.settings, day)
        let found: Int? = all.firstIndex { (x: Found) -> Bool in x.it.id == next.it.id }
        let at: Int = found ?? 0
        let from: String = at == 0 ? "住的地方" : all[at - 1].it.n
        if at < legs.count, let l = legs[at] {
            return "從\(from)・\(l.mode)・\(l.min) 分鐘（估）"
        }
        return "從\(from)過去的距離不明，到時候查地圖"
    }

    /// 下一站之後的那一站，點了進一站
    private func afterRow(_ x: Found) -> some View {
        Button {
            nav.push(.stop(id: x.it.id))
        } label: {
            HStack(spacing: T.Space.s3) {
                DomyText("之後・\(PART[need: x.s.part])・\(x.it.n)", .subheadline)
                    .fillLeading()
                Chevron()
            }
            .padding(.vertical, T.Space.s3)
            .padding(.horizontal, T.Space.s4)
            .frame(minHeight: T.Size.touch)
            .background(C.surface, in: RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
        .accessibilityIdentifier("next-after")
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
