// 移到別的時段（S07，線框 .uiux/03-線框/線框/A6-Move）：半頁。每一天一列、上午下午晚上三格，
// 在路上的時段不能選，這一站現在在的那一格寫「現在在這」。選好一格，下面寫那天現在有幾個主要景點、共幾站，
// 移過去之後主要景點會超過 2 個就先講；這一站那天休館也講（那一列寫休館，選了寫為什麼），不擋。
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
    private let id: String

    init(id: String) {
        self.id = id
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
        .presentationDetents([.fraction(0.7), .large])  // domy-ignore: 半頁高度照 A6，五天的格子放得下
    }

    /// 這一站剛被拿掉或換掉了（例：用講的改掉了）
    private var gone: some View {
        SheetScaffold("移到別的時段", onClose: { sheets.close() }) {
            DomyText("這一站不在這趟裡了，可能剛被拿掉或換掉。", .body, tone: .secondary)
        }
    }

    private func page(_ trip: Trip, _ found: Found) -> some View {
        SheetScaffold("把「\(found.it.n)」移到", scroll: false, onClose: { sheets.close() }) {
            DomyText(
                "現在在第 \(found.s.day) 天\(PART[need: found.s.part])。在路上的時段不能選。",
                .footnote, tone: .secondary)
            ScrollView {
                MoveGrid(trip: trip, from: found, to: to) { (next: MoveTarget) -> Void in
                    Haptic.select()
                    to = next
                }
                .padding(.vertical, T.Space.s1)
            }
            MoveSummary(trip: trip, it: found.it, from: found.s, to: to)
            actions(found)
        }
    }

    private func actions(_ found: Found) -> some View {
        HStack(spacing: T.Space.s2) {
            DomyButton(to == nil ? "先選一個時段" : "移過去", disabled: to == nil, fullWidth: true) {
                move(found.it.n)
            }
            .accessibilityIdentifier("move-go")
            DomyButton("取消", variant: .secondary, fullWidth: true) {
                sheets.close()
            }
            .accessibilityIdentifier("move-cancel")
        }
    }

    private func move(_ name: String) {
        guard let to else { return }
        let stopId: String = id
        let day: Int = to.day
        let part: Part = to.part
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = moveItem(&trip, stopId, day, part)
            d.trip = trip
            if let err { return err }
            // 只講移去的那一天：別天本來就太滿的，跟這一步沒關係
            var done: String = "「\(name)」移到第 \(day) 天\(PART[need: part])了。"
            if let why = moveClosed(trip, stopId, day) { done += "那天它休館：\(why)。" }
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
    let onPick: (MoveTarget) -> Void

    private var days: [Int] {
        Array(stride(from: 1, through: trip.days, by: 1))
    }

    var body: some View {
        Grid(horizontalSpacing: T.Space.s2, verticalSpacing: T.Space.s2) {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                ForEach(PARTS, id: \.self) { (p: Part) in
                    DomyText(PART[need: p], .footnote, tone: .secondary, align: .center)
                        .frame(maxWidth: .infinity)
                }
            }
            ForEach(days, id: \.self) { (d: Int) in
                GridRow {
                    dayLabel(d)
                    ForEach(PARTS, id: \.self) { (p: Part) in
                        MoveCell(state: state(d, p), day: d, part: p, closed: moveClosed(trip, from.it.id, d)) {
                            onPick(MoveTarget(day: d, part: p))
                        }
                    }
                }
            }
        }
    }

    private func dayLabel(_ d: Int) -> some View {
        let date: String = fmtDay(addDays(trip.start, d - 1))
        return VStack(alignment: .leading, spacing: 0) {
            DomyText("第 \(d) 天", .subheadline, weight: .semibold, lines: 1)
            DomyText(date, .caption, tone: .secondary, lines: 1)
            if moveClosed(trip, from.it.id, d) != nil {
                DomyText("休館", .caption, tone: .destructive, lines: 1)
            }
        }
        .gridColumnAlignment(.leading)
        .accessibilityElement(children: .combine)
    }

    private func state(_ d: Int, _ p: Part) -> MoveCellState {
        guard let si = slotAt(trip, d, p) else { return .off }
        if si == from.si { return .here }
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
    case open(count: Int, picked: Bool)
}

/// 一格。選到的用粗框加勾（A6 畫的時候定的），實心底留給「移過去」
private struct MoveCell: View {
    let state: MoveCellState
    let day: Int
    let part: Part
    /// 這一站那天不開的原因。格子照樣能選，只讓旁白念出來
    let closed: String?
    let action: () -> Void

    private var title: String {
        switch state {
        case .off: return "在路上"
        case .here: return "現在在這"
        case .open(let count, _): return count == 0 ? "空著" : "\(count) 站"
        }
    }

    private var picked: Bool {
        if case .open(_, let p) = state { return p }
        return false
    }

    private var enabled: Bool {
        if case .open = state { return true }
        return false
    }

    private var a11y: String {
        let at: String = "第 \(day) 天\(PART[need: part])"
        let shut: String = closed.map { (why: String) -> String in "，這天休館：\(why)" } ?? ""
        switch state {
        case .off: return "\(at)，在路上，不能選"
        case .here: return "\(at)，這一站現在在這" + shut
        case .open: return "\(at)，\(title)" + shut + (picked ? "，選了" : "")
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        Button(action: action) {
            HStack(spacing: T.Space.s1) {
                if picked {
                    Image(systemName: "checkmark")
                        .font(T.TypeScale.footnote.font.weight(.bold))
                        .foregroundStyle(C.strong)
                        .accessibilityHidden(true)
                }
                DomyText(title, enabled ? .subheadline : .footnote, tone: tone, weight: picked ? .bold : nil, lines: 1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: T.Size.button)
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
        case .off: return .disabled
        case .here: return .primary
        case .open: return picked ? .strong : .primary
        }
    }

    private var fill: Color {
        switch state {
        case .off: return C.surfaceMuted
        case .here: return C.soft
        case .open: return C.surface
        }
    }

    private var border: Color {
        if picked { return C.strong }
        return state == .off ? Color.clear : C.fieldBorder
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
                    DomyText("這天休館：\(why)", .subheadline, tone: .destructive)
                        .accessibilityIdentifier("move-closed")
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
    }

    /// 這一站是主要景點、移到別天，那天會超過 2 個
    private func tooMany(_ to: MoveTarget) -> String? {
        if it.s != .L || to.day == from.day { return nil }
        let after: Int = bigCount(trip, to.day) + 1
        if after <= 2 { return nil }
        return "移過去之後第 \(to.day) 天會有 \(after) 個主要景點，會很累。還是可以移。"
    }
}
