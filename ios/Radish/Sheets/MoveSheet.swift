// 移到別的時段（S07，線框 .uiux/03-線框/線框/A6-Move）：半頁。每一天一列、上午下午晚上三格，
// 在路上的時段不能選；旅途中已經過了的時段也不能選（格子寫「已經過了」，規則在 moveItem 也擋），這一站現在在的那一格寫「現在在這」。選好一格，下面寫那天現在有幾個主要景點、共幾站，
// 移過去之後主要景點會超過 2 個就先講；這一站那天不開、那個時段不開也講（那一列、那一格標出來，選了寫為什麼），不擋。
// 移過去之後關掉，提示條帶復原。
// 開法：sheets.open(.move(id:))。原本是 mobile/src/sheets/StopSheet.tsx 的 move 那一面（Sheets/StopSheetParts.swift 的 StopSheetMove）。
import SwiftUI

/// 選到的那一格
struct MoveTarget: Equatable {
    var day: Int
    var part: Part
}

/// 這一站那天不開的原因
private func moveClosed(_ trip: Trip, _ id: String, _ day: Int) -> String? {
    return closedOnTripDay(trip.start, day, id, closedByFacts)
}

struct MoveSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    /// 還沒選是 nil：「移過去」不能按
    @State private var to: MoveTarget?
    @Environment(\.dynamicTypeSize) private var typeSize
    private let id: String

    init(id: String) {
        self.id = id
    }

    /// 旅途中的現在；出發前、回來後是 nil。它之前的時段不能選
    private var now: TripNow? {
        guard let phase = store.phase else { return nil }
        return tripNow(chatClock(phase))
    }

    var body: some View {
        Group {
            if let trip = store.s.trip, let found = findItem(trip, id) {
                page(trip, found)
            } else {
                gone
            }
        }
        .onChange(of: store.s.trip?.id) { (_: String?, _: String?) in
            // 半頁開著的時候換了一趟：選的那一格是上一趟的，重選
            to = nil
        }
        .presentationDetents(detents)
    }

    /// 輔助使用的大字：一開就是整張高，格子才看得到幾列
    private var detents: Set<PresentationDetent> {
        if typeSize.isAccessibilitySize { return [.large] }
        return [.fraction(0.82), .large]  // domy-ignore: A6 是 0.7，五天的格子放不下，加高
    }

    /// 這一站剛被拿掉或換掉了（例：用講的改掉了）
    private var gone: some View {
        SheetScaffold("移到別的時段", onClose: { sheets.close() }) {
            DomyText("這一站不在這趟裡了，可能剛被拿掉或換掉。", .body, tone: .secondary)
        }
    }

    private func page(_ trip: Trip, _ found: Found) -> some View {
        // 輔助使用的大字標題放不下站名，會被切：標題寫短的，站名寫在下面那句
        let big: Bool = typeSize.isAccessibilitySize
        return SheetScaffold(big ? "移到別的時段" : "把「\(found.it.n)」移到", scroll: false, onClose: { sheets.close() }) {
            if !typeSize.isAccessibilitySize {
                note(found)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: T.Space.s4) {
                    // 輔助使用的大字跟著格子一起捲，把位置讓給格子
                    if typeSize.isAccessibilitySize {
                        note(found)
                    }
                    MoveGrid(trip: trip, from: found, to: to, now: now) { (next: MoveTarget) -> Void in
                        Haptic.select()
                        to = next
                    }
                }
                .padding(.vertical, T.Space.s1)
            }
            // 天數多、字放大的時候放不下：打開時捲軸閃一下，看得出可以捲
            .scrollIndicators(.visible)
            .scrollIndicatorsFlash(onAppear: true)
            MoveSummary(trip: trip, it: found.it, from: found.s, to: to)
            actions(found)
        }
    }

    private func note(_ found: Found) -> some View {
        let name: String = typeSize.isAccessibilitySize ? "「\(found.it.n)」" : ""
        let cannot: String = now == nil ? "在路上的時段不能選。" : "在路上、已經過了的時段不能選。"
        return DomyText(
            "\(name)現在在第 \(found.s.day) 天\(PART[need: found.s.part])。\(cannot)",
            .footnote, tone: .secondary)
    }

    private func actions(_ found: Found) -> some View {
        // 字級放大時兩顆放不下，改成一顆一列
        PairLayout(spacing: T.Space.s2) {
            DomyButton(to == nil ? "先選一個時段" : "移過去", disabled: to == nil, fullWidth: true) {
                move(found.it)
            }
            .accessibilityIdentifier("move-go")
            DomyButton("取消", variant: .secondary, fullWidth: true) {
                sheets.close()
            }
            .accessibilityIdentifier("move-cancel")
        }
    }

    private func move(_ it: Stop) {
        guard let to else { return }
        let stopId: String = id
        let name: String = it.n
        let words: KindWords = kindWords(it.c)
        let day: Int = to.day
        let part: Part = to.part
        // 按下那一刻的現在：半頁開著的時候那個時段過了，就不移
        let at: TripNow? = now
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = moveItem(&trip, stopId, day, part, at)
            d.trip = trip
            if let err { return err }
            // 只講移去的那一天：別天本來就太滿的，跟這一步沒關係
            var done: String = "「\(name)」移到第 \(day) 天\(PART[need: part])了。"
            if let why = moveClosed(trip, stopId, day) {
                done += "那天它\(words.shut)：" + fullStop(why)
            } else if let why = tripPartShut(trip, stopId, day, part) {
                done += fullStop(why)
            }
            let big: Int = bigCount(trip, day)
            if big > 2 { return done + "那天現在有 \(big) 個主要景點，會很累。" }
            return done
        }
        sheets.close()
    }
}

/// 天數 × 三個時段的格子
private struct MoveGrid: View {
    let trip: Trip
    let from: Found
    let to: MoveTarget?
    /// 旅途中的現在。它之前的時段不能選
    let now: TripNow?
    let onPick: (MoveTarget) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var days: [Int] {
        Array(stride(from: 1, through: trip.days, by: 1))
    }

    /// 輔助使用的大字：天數自己一行在上面，三格分整張的寬，時段寫進格子裡
    private var big: Bool {
        return typeSize.isAccessibilitySize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: big ? T.Space.s5 : T.Space.s2) {
            if !big {
                header
            }
            ForEach(days, id: \.self) { (d: Int) in
                dayRow(d)
            }
        }
    }

    private var header: some View {
        HStack(spacing: T.Space.s2) {
            labelColumn {
                Color.clear
                    .frame(width: 0, height: 0)
            }
            ForEach(PARTS, id: \.self) { (p: Part) in
                DomyText(PART[need: p], .footnote, tone: .secondary, align: .center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayRow(_ d: Int) -> some View {
        if big {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                dayLabel(d)
                // 字會換行，三格照最高的那格一樣高
                HStack(spacing: T.Space.s2) {
                    cells(d)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            HStack(spacing: T.Space.s2) {
                labelColumn {
                    dayLabel(d)
                }
                cells(d)
            }
        }
    }

    private func cells(_ d: Int) -> some View {
        return ForEach(PARTS, id: \.self) { (p: Part) in
            MoveCell(
                state: state(d, p), day: d, part: p, shut: shutText(d),
                partShut: tripPartShut(trip, from.it.id, d, p)
            ) {
                onPick(MoveTarget(day: d, part: p))
            }
        }
    }

    /// 最前面那一欄。每一列都疊著全部的天數（看不見的），寬度照最長的那個，日期不會被切、三格一樣寬
    private func labelColumn<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        return ZStack(alignment: .leading) {
            ZStack(alignment: .leading) {
                ForEach(days, id: \.self) { (d: Int) in
                    dayLabel(d)
                }
            }
            .frame(height: 0)
            .hidden()
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// 這一天整天都過了（晚上也過了）：不用再講那天開不開
    private func dayGone(_ d: Int) -> Bool {
        return slotPast(now, d, .eve)
    }

    /// 那天整天不開，給旁白念的。有開、整天都過了是 nil
    private func shutText(_ d: Int) -> String? {
        if dayGone(d) { return nil }
        guard let why = moveClosed(trip, from.it.id, d) else { return nil }
        return "這天\(kindWords(from.it.c).shut)：\(why)"
    }

    private func dayLabel(_ d: Int) -> some View {
        return VStack(alignment: .leading, spacing: 0) {
            // 不開寫在「第幾天」旁邊，列才不會變高。字放大時排不下，改成三行；輔助使用的大字整張寬，排成一行
            if big {
                TagRow {
                    dayText(d)
                    dateText(d)
                    offText(d)
                }
            } else if typeSize > DynamicTypeSize.xLarge {
                dayText(d)
                dateText(d)
                offText(d)
            } else {
                HStack(spacing: T.Space.s1) {
                    dayText(d)
                    offText(d)
                }
                dateText(d)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func dayText(_ d: Int) -> some View {
        return DomyText("第 \(d) 天", .subheadline, weight: .semibold, lines: 1)
    }

    private func dateText(_ d: Int) -> some View {
        return DomyText(fmtDay(addDays(trip.start, d - 1)), .caption, tone: .secondary, lines: 1)
    }

    @ViewBuilder
    private func offText(_ d: Int) -> some View {
        if !dayGone(d), moveClosed(trip, from.it.id, d) != nil {
            DomyText(kindWords(from.it.c).off, .caption, tone: .destructive, lines: 1)
        }
    }

    private func state(_ d: Int, _ p: Part) -> MoveCellState {
        guard let si = slotAt(trip, d, p) else { return .off }
        if si == from.si { return .here }
        if slotPast(now, d, p) { return .past }
        let count: Int = trip.slots[si].items.count
        let picked: Bool = to == MoveTarget(day: d, part: p)
        return .open(count: count, picked: picked)
    }
}

private enum MoveCellState: Equatable {
    /// 在路上，不能選
    case off
    /// 這一站現在在的那一格
    case here
    /// 旅途中已經過了的時段，不能選
    case past
    case open(count: Int, picked: Bool)
}

/// 一格。選到的用粗框加勾（A6 畫的時候定的），實心底留給「移過去」
private struct MoveCell: View {
    let state: MoveCellState
    let day: Int
    let part: Part
    /// 這一站那天整天不開。那一列前面寫了，這裡只讓旁白念出來；格子照樣能選
    let shut: String?
    /// 只有這個時段不開。格子裡多一行「不開」，選了下面寫為什麼
    let partShut: String?
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 輔助使用的大字沒有上面那排時段，時段寫進格子裡
    private var showsPart: Bool {
        return typeSize.isAccessibilitySize
    }

    /// 字放大時一行放不下「現在在這」，准換行
    private var titleLines: Int? {
        return typeSize > DynamicTypeSize.xLarge ? nil : 1
    }

    private var title: String {
        switch state {
        case .off: return "在路上"
        case .here: return "現在在這"
        case .past: return "已經過了"
        case .open(let count, _): return count == 0 ? "空著" : "\(count) 站"
        }
    }

    private var picked: Bool {
        if case .open(_, let p) = state { return p }
        return false
    }

    private var showsPartShut: Bool {
        return partShut != nil && state != .off && state != .past
    }

    /// 在路上、已經過了：灰掉不能選
    private var dimmed: Bool {
        return state == .off || state == .past
    }

    private var enabled: Bool {
        if case .open = state { return true }
        return false
    }

    private var a11y: String {
        let at: String = "第 \(day) 天\(PART[need: part])"
        let why: String = (shut ?? partShut).map { (x: String) -> String in "，" + x } ?? ""
        switch state {
        case .off: return "\(at)，在路上，不能選"
        case .here: return "\(at)，這一站現在在這" + why
        case .past: return "\(at)，已經過了，不能選"
        case .open: return "\(at)，\(title)" + why + (picked ? "，選了" : "")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        Button(action: action) {
            VStack(spacing: 0) {
                if showsPart {
                    DomyText(PART[need: part], .caption, tone: dimmed ? .disabled : .secondary, lines: 1)
                }
                HStack(spacing: T.Space.s1) {
                    if picked {
                        Image(systemName: "checkmark")
                            .font(T.TypeScale.footnote.font.weight(.bold))
                            .foregroundStyle(C.strong)
                            .accessibilityHidden(true)
                    }
                    DomyText(
                        title, enabled ? .subheadline : .footnote, tone: tone, weight: picked ? .bold : nil,
                        lines: titleLines, align: .center)
                }
                if showsPartShut {
                    DomyText("不開", .caption, tone: .destructive, lines: 1)
                }
            }
            .padding(.vertical, showsPart ? T.Space.s2 : 0)
            .frame(maxWidth: .infinity, minHeight: T.Size.button, maxHeight: showsPart ? .infinity : nil)
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: picked ? T.Size.hairline * 2 : T.Size.hairline))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle())
        .disabled(!enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityAddTraits(picked ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("move-\(day)-\(part.rawValue)")
    }

    private var tone: TextTone {
        switch state {
        case .off, .past: return .disabled
        case .here: return .primary
        case .open: return picked ? .strong : .primary
        }
    }

    private var fill: Color {
        switch state {
        case .off, .past: return C.surfaceMuted
        case .here: return C.soft
        case .open: return C.surface
        }
    }

    private var border: Color {
        if picked { return C.strong }
        return dimmed ? Color.clear : C.fieldBorder
    }
}

/// 格子下面那一塊：選到的那天現在有幾個主要景點、共幾站。主要景點移過去會超過 2 個就先講
private struct MoveSummary: View {
    let trip: Trip
    let it: Stop
    let from: Slot
    let to: MoveTarget?

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s1) {
            if let to {
                DomyText("第 \(to.day) 天現在有 \(bigCount(trip, to.day)) 個主要景點、共 \(dayStops(trip, to.day).count) 站", .subheadline)
                if let why = moveClosed(trip, it.id, to.day) {
                    DomyText("這天\(kindWords(it.c).shut)：\(why)", .subheadline, tone: .destructive)
                } else if let why = tripPartShut(trip, it.id, to.day, to.part) {
                    DomyText(why, .subheadline, tone: .destructive)
                }
                if let warn = tooMany(to) {
                    DomyText(warn, .subheadline, tone: .destructive)
                }
            } else {
                DomyText("點一格選要移去哪裡。", .subheadline, tone: .secondary)
            }
        }
        .padding(.vertical, T.Space.s2 + T.Space.s1 / 2)
        .padding(.horizontal, T.Space.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.surfaceMuted, in: RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(mark)
    }

    /// 整塊併成一個念，識別碼要掛在整塊上：選了那天不開、那個時段不開的，各自一個
    private var mark: String {
        guard let to else { return "move-summary" }
        if moveClosed(trip, it.id, to.day) != nil { return "move-closed" }
        if tripPartShut(trip, it.id, to.day, to.part) != nil { return "move-part-closed" }
        return "move-summary"
    }

    /// 這一站是主要景點、移到別天，那天會超過 2 個
    private func tooMany(_ to: MoveTarget) -> String? {
        if it.s != .L || to.day == from.day { return nil }
        let after: Int = bigCount(trip, to.day) + 1
        if after <= 2 { return nil }
        return "移過去之後第 \(to.day) 天會有 \(after) 個主要景點，會很累。還是可以移。"
    }
}
