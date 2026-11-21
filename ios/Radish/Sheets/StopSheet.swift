// 一站的卡：為什麼排它、須知、當地文字、找路，還有移走、換一個、這次不去。
// 對應 mobile/src/sheets/StopSheet.tsx。每一種模式的畫面在 StopSheetParts.swift。
import SwiftUI

/// TS 的 Mode：這張卡現在顯示哪一面
enum StopSheetMode {
    case main, move, swap, show, drop, allergy
}

/// 「移到別的時段」選到的那一格
struct StopMoveTarget: Equatable {
    var day: Int
    var part: Part
}

struct StopSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @State private var mode: StopSheetMode = .main
    @State private var copied: Bool = false
    /// 還沒選過就是 nil，用這一站現在所在的那一格
    @State private var to: StopMoveTarget?
    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        if let trip = store.s.trip, let found = findItem(trip, id) {
            page(trip, found)
        } else {
            gone
        }
    }

    /// 找不到這一站（剛被拿掉或換掉）：TS 是什麼都不顯示。這裡留一張空白的卡，還開著就關掉
    private var gone: some View {
        C.canvas
            .ignoresSafeArea()
            .onAppear {
                if sheets.req == SheetReq.stop(id: id) {
                    sheets.close()
                }
            }
    }

    @ViewBuilder
    private func page(_ trip: Trip, _ found: Found) -> some View {
        let it: Stop = found.it
        let back: () -> Void = { mode = .main }
        let choices: [LearnChoice] = learnChoices(it, store.s.settings)
        let dropIt: (LearnChoice?) -> Void = { (choice: LearnChoice?) -> Void in
            drop(it.n, choice)
        }
        switch mode {
        case .main:
            StopSheetMain(
                id: id, it: it, slot: found.s, trip: trip, choices: choices, copied: $copied,
                setMode: { (next: StopSheetMode) -> Void in mode = next }, drop: dropIt)
        case .allergy:
            SheetScaffold("過敏告知卡", onClose: back) {
                AllergyCardView(list: tripSettings(store.s.settings, trip.tweaks).allergy)
            }
        case .drop:
            StopSheetDrop(it: it, choices: choices, back: back, drop: dropIt)
        case .show:
            StopSheetShow(it: it, back: back)
        case .move:
            StopSheetMove(id: id, it: it, trip: trip, to: target(found.s), back: back)
        case .swap:
            StopSheetSwap(id: id, it: it, trip: trip, back: back)
        }
    }

    private func target(_ slot: Slot) -> Binding<StopMoveTarget> {
        Binding(
            get: { to ?? StopMoveTarget(day: slot.day, part: slot.part) },
            set: { (next: StopMoveTarget) -> Void in to = next })
    }

    /// 拿掉這一站。choice 有給的話，順便記成「以後都不排」；兩件事算同一步，可以一起復原
    private func drop(_ name: String, _ choice: LearnChoice?) {
        Haptic.impact(.light)
        let stopId: String = id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let choice else {
                var seeds: [Seed] = d.seeds
                _ = seedOut(&trip, &seeds, stopId, "你說這次不去")
                d.trip = trip
                d.seeds = seeds
                return "「\(name)」放到下次再來了。"
            }
            guard let x = findItem(trip, stopId) else { return nil }
            trip.slots[x.si].items.remove(at: x.ii)
            if trip.slots[x.si].items.isEmpty {
                trip.slots[x.si].rest = true
            }
            d.trip = trip
            var settings: Settings = d.settings
            _ = learn(&settings, choice, "\(tripTitle(trip))：你拿掉了\(name)")
            d.settings = settings
            let tail: String = choice.kind == .place ? "" : "這趟已經排的其他站沒動。"
            return "「\(name)」拿掉了。以後\(learnedText(choice))，在「我」可以拿掉這一條。\(tail)"
        }
        sheets.close()
    }
}
