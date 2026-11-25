// 一站（S06，線框 .uiux/03-線框/線框/A5-Stop）：推進頁。建議停留、須知、預估花費、韓文名、找路、移到別的時段、換一個，
// 照線框的順序；核對資料的開放／怎麼訂／來源（有查到才有）排在後面，不把要按的擠到後面幾頁。
// QC-0013：不再顯示「為什麼排」；照片（去沒去過都能加）和「在這裡花的」在 StopScreenMine.swift。
// 右上角是不想去這一站。最下面掛跟 AI 講的那一列（小標是站名）。
// 原本是彈出卡 mobile/src/sheets/StopSheet.tsx（SwiftUI 版的 Sheets/StopSheet.swift），2026-11-23 改成推進頁。
// 這趟裡找不到的話改查首爾資料包（附近還有什麼的「看那站」、剛拿掉又從舊的入口進來的），只給看。
// 每一塊的畫面在 StopScreenParts.swift；換一個、不去這一站、過敏告知卡是這一頁自己開的半頁，給司機看是全螢幕。
import SwiftUI

/// 這一頁自己開的半頁。移到別的時段走 Sheets 的 .move(id:)，不在這裡
enum StopPane: String, Identifiable {
    case swap, drop, allergy

    var id: String { rawValue }
}

struct StopScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    private let id: String

    init(id: String) {
        self.id = id
    }

    var body: some View {
        let trip: Trip? = store.s.trip
        let found: Found? = trip.flatMap { (t: Trip) -> Found? in findItem(t, id) }
        let place: Place? = found == nil ? PLACES.first(where: { (p: Place) -> Bool in p.id == id }) : nil
        Group {
            if let trip, let found {
                StopPage(id: id, trip: trip, found: found)
            } else if let place {
                // 不在這趟裡的地方，只給看：附近還有什麼的「看那站」，或剛拿掉、從舊的入口進來的
                StopPreview(place: place)
            } else {
                StopGone()
            }
        }
        // 剛被拿掉、換掉（在這頁按的、或用講的改掉的）：這一站不在這趟裡了，回上一頁。提示條上有復原
        .onChange(of: found != nil) { (old: Bool, new: Bool) in
            if old && !new {
                dismiss()
            }
        }
    }
}

/// 進來的時候這一站就已經不在了（例：剛復原過、從舊的入口點進來）
private struct StopGone: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Screen("這一站") {
            DomyEmptyState(
                icon: IconPaths.sprout,
                title: "這一站已經不在這趟了",
                message: "可能剛被拿掉或換掉了。拿掉的站會在「下次再來」，可以排回來。",
                actionTitle: "回上一頁",
                action: { dismiss() }
            )
        }
    }
}

/// 不在這趟裡的地方（首爾資料包 PLACES 裡的）：建議停留、須知、預估花費、韓文名、給司機看、Naver，
/// 跟這趟裡的站一樣，開放／怎麼訂／來源排在要按的後面。
/// 不給移時段、換一個、不想去、拔起來；要排進來在附近還有什麼那張半頁按
private struct StopPreview: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    let place: Place

    @State private var driver: Bool = false
    @State private var allergy: Bool = false

    private var it: Stop {
        planToStop(place, why)
    }

    /// 歇業了。不在這趟裡沒有日期，看不出哪天休館
    private var shut: StopShut? {
        placeShut(place.id)
    }

    /// 放在「下次再來」
    private var later: Bool {
        let placeId: String = place.id
        return store.s.seeds.contains { (x: Seed) -> Bool in x.stop?.id == placeId }
    }

    /// 這一頁不知道是從哪裡點進來的，只講確定的事。畫面上不顯示（QC-0013），換成上面的小標籤
    private var why: String {
        if later {
            return "現在不在這趟裡，放在「下次再來」。"
        }
        return "現在不在這趟裡。這是首爾資料包裡的地點。"
    }

    var body: some View {
        Screen(place.n) {
            header
                .padding(.top, -T.Space.s4)
            StopInfoSection(
                it: it, hasOpen: opensKnown(factOf(place.id), place.c, shut), noBook: bookUnknown(it, shut))
            if let trip = store.s.trip {
                StopAllergyEntry(it: it, trip: trip) {
                    allergy = true
                }
            }
            StopPlaceCard(it: it) {
                driver = true
            }
            StopFactBlocks(it: it, shut: shut, visit: nil)
            StopOtherMaps(it: it)
        }
        .sheet(isPresented: $allergy) {
            SheetScaffold("過敏告知卡", onClose: { allergy = false }) {
                AllergyCardView(list: tripSettings(store.s.settings, store.s.trip?.tweaks).allergy)
            }
            .presentationDetents([.fraction(0.75), .large])  // domy-ignore: 半頁高度照 A13
            .environment(store)
            .environment(sheets)
            .environment(nav)
            .tint(C.accent)
        }
        .fullScreenCover(isPresented: $driver) {
            DriverView(name: place.n, kr: place.kr, addr: factOf(place.id)?.addr)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            HStack(alignment: .center, spacing: T.Space.s3) {
                CatIcon(place)
                DomyText("\(AREA[need: place.a])・\(kindName(place))", .subheadline, tone: .secondary)
                    .fillLeading()
            }
            if let shut {
                WarnTag(shut.why)
                    .accessibilityIdentifier("stop-closed")
            }
            TagRow {
                Tag("不在這趟裡", tone: .accent)
                if later {
                    Tag("放在下次再來")
                }
                Tag(place.s == .L ? "主要景點" : "順路小地方")
                if place.b == true {
                    Tag("要先訂", tone: .accent)
                }
            }
        }
    }
}

/// 找得到這一站時的整頁
private struct StopPage: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    let id: String
    let trip: Trip
    let found: Found

    @State private var pane: StopPane?
    @State private var driver: Bool = false
    /// 半頁收起來之後才做的事（拿掉、換掉）。在半頁還開著的時候改行程，這一頁會在收半頁的同時被拿掉，兩個動畫會撞在一起
    @State private var afterPane: (() -> Void)?

    private var it: Stop { found.it }

    private var choices: [LearnChoice] {
        learnChoices(it, store.s.settings)
    }

    var body: some View {
        Screen(it.n) {
            content
        }
        .toolbar {
            // 去過了的站不能拿掉（要先按「按錯了，這站還沒去」）
            if it.status == .kept {
                ToolbarItem(placement: .topBarTrailing) {
                    removeButton
                }
            }
        }
        .talkBar(it.n, target: .stop(id: id))
        .sheet(item: $pane, onDismiss: runAfterPane) { (p: StopPane) in
            paneView(p)
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
        }
        .fullScreenCover(isPresented: $driver) {
            DriverView(name: it.n, kr: it.kr, addr: factOf(it.id)?.addr)
        }
    }

    /// 這一站那天去不了（休館、歇業）。去得了、去過了是 nil
    private var shut: StopShut? {
        stopShut(trip, it, found.s.day, store.phase)
    }

    /// 排的這個時段不開。那天整天不開的只講那天不開
    private var partShut: String? {
        stopPartShut(trip, it, found.s, store.phase)
    }

    /// 那天要注意、但不算不開的
    private var caution: String? {
        stopCaution(trip, it, found.s.day, store.phase)
    }

    /// 去這一站的那天，YYYY-MM-DD
    private var visit: String {
        addDays(trip.start, found.s.day - 1)
    }

    @ViewBuilder
    private var content: some View {
        StopHeader(it: it, trip: trip, slot: found.s, shut: shut, partShut: partShut, caution: caution)
            .padding(.top, -T.Space.s4)
        StopInfoSection(
            it: it, hasOpen: opensKnown(factOf(it.id), it.c, shut), noBook: bookUnknown(it, shut))
        StopAllergyEntry(it: it, trip: trip) {
            pane = .allergy
        }
        // 去過了：那一句、照片、花的排在一起，先寫回憶；還沒去：要按的（找路、移時段、換一個）先，照片和花的放後面
        if it.status == .pulled {
            StopVisitBlock(id: id, it: it, tripId: trip.id)
            mine
            StopPlaceCard(it: it) {
                driver = true
            }
            edit
        } else {
            StopPlaceCard(it: it) {
                driver = true
            }
            edit
            mine
        }
        StopFactBlocks(it: it, shut: shut, visit: visit)
        StopOtherMaps(it: it)
    }

    private var edit: some View {
        StopEditBlock(
            id: id, it: it, trip: trip,
            onSwap: { pane = .swap })
    }

    /// 自己加的照片、在這裡花的
    @ViewBuilder
    private var mine: some View {
        StopPhotoBlock(id: id, it: it, tripId: trip.id)
        StopSpendBlock(id: id, it: it, trip: trip, day: found.s.day)
    }

    /// 右上角「不想去這一站」。跟移到別的時段、換一個分開放（.uiux/03-線框/方向說明-暫定.md：A5 畫的時候定的）
    private var removeButton: some View {
        Button {
            if choices.isEmpty {
                // 自己加的、AI 加的站沒有東西可以記成「以後不排」，直接放到下次再來，提示條上有復原
                drop(nil)
            } else {
                pane = .drop
            }
        } label: {
            // 導覽列會幫它畫一顆膠囊底，左右留一點空，字才不會貼邊
            DomyText("不想去這一站", .body, tone: .strong, lines: 1)
                .padding(.horizontal, T.Space.s2)
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("stop-remove")
    }

    @ViewBuilder
    private func paneView(_ p: StopPane) -> some View {
        switch p {
        case .swap:
            StopSwapPane(
                it: it, trip: trip,
                onPick: { (place: Place) -> Void in later { swap(place) } },
                onClose: { pane = nil })
        case .drop:
            StopDropPane(
                it: it, choices: choices,
                onPick: { (choice: LearnChoice?) -> Void in later { drop(choice) } },
                onClose: { pane = nil })
        case .allergy:
            SheetScaffold("過敏告知卡", onClose: { pane = nil }) {
                AllergyCardView(list: tripSettings(store.s.settings, trip.tweaks).allergy)
            }
            // 半頁，上面還看得到這一站（線框 A13）。韓文五行要一次看完，比系統的半頁高一點
            .presentationDetents([.fraction(0.75), .large])  // domy-ignore: 半頁高度照 A13
        }
    }

    /// 先收半頁，收完再做
    private func later(_ f: @escaping () -> Void) {
        afterPane = f
        pane = nil
    }

    private func runAfterPane() {
        let f: (() -> Void)? = afterPane
        afterPane = nil
        f?()
    }

    /// 拿掉這一站。choice 有給的話，順便記成「以後都不排」；兩件事算同一步，可以一起復原
    private func drop(_ choice: LearnChoice?) {
        Haptic.impact(.light)
        let stopId: String = id
        let name: String = it.n
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
            return "「\(name)」拿掉了。以後\(learnedText(choice))，在「平常的我」可以拿掉這一條。\(tail)"
        }
    }

    /// 換成候選的那一個。換完這一站的代號會變，這一頁會自己回上一頁
    private func swap(_ p: Place) {
        let stopId: String = id
        let name: String = it.n
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            let err: String? = replaceWith(&trip, stopId, p)
            d.trip = trip
            return err ?? "「\(name)」換成「\(p.n)」了。"
        }
    }
}
