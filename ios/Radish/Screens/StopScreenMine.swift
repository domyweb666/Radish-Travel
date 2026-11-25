// 一站頁（StopScreen.swift）裡使用者自己的東西：照片（去沒去過都能加，QC-0013 #96、#100）、
// 在這裡花的（好幾筆、韓元或台幣，QC-0013 #106）。mobile/ 沒有對應的 TS。
// 照片沿用 Stop.photos 和 IO/Photos.swift 的 PhotoStore；花的記在整趟的 trip.spend（多記這一站的代號），
// 花費頁的合計一起算。加、刪都留一步可以復原。
import SwiftUI

// MARK: - 改這一站

/// 改這一站自己的東西。畫面畫出來之後可能換了一趟、這一站被拿掉，每次都照現在的行程找
@MainActor
struct StopPatch {
    let store: AppStore
    let id: String
    /// 這一塊畫的是哪一趟
    let tripId: String?

    /// 這一塊畫出來之後換了一趟（例：按了提示條的復原）
    var moved: Bool {
        return store.s.trip?.id != tripId
    }

    /// 這一站現在的樣子。被拿掉、換掉了就是 nil
    var now: Stop? {
        guard let trip = store.s.trip else { return nil }
        return findItem(trip, id)?.it
    }

    /// 改這一站，留一步可以復原
    func change(_ msg: String, _ edit: (inout Stop) -> Void) {
        let stopId: String = id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let x = findItem(trip, stopId) else { return nil }
            edit(&trip.slots[x.si].items[x.ii])
            d.trip = trip
            return msg
        }
    }
}

// MARK: - 照片

/// 點了哪一張要看大圖
struct StopPhotoPick: Identifiable {
    let ref: String
    let index: Int

    var id: String { ref }
}

/// 一個虛線的「加照片」方塊，右邊橫排已經加的縮圖。點縮圖看大圖，大圖下面可以刪
struct StopPhotoBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @Environment(Nav.self) private var nav
    let id: String
    let it: Stop
    let tripId: String?

    @State private var viewing: StopPhotoPick?

    private var patch: StopPatch {
        StopPatch(store: store, id: id, tripId: tripId)
    }

    var body: some View {
        let photos: [String] = it.photos ?? []
        Card {
            FieldLabel(photos.isEmpty ? "照片" : "照片（\(photos.count) 張）")
            strip(photos)
            DomyText("照片會縮小後存在這支手機裡，沒網路也看得到。不會上傳到任何地方。", .footnote, tone: .secondary)
        }
        .sheet(item: $viewing) { (v: StopPhotoPick) in
            viewer(v)
                .environment(store)
                .environment(sheets)
                .environment(nav)
                .tint(C.accent)
        }
    }

    private func strip(_ photos: [String]) -> some View {
        let edge: CGFloat = T.Size.heroButton / 2
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: T.Space.s2) {
                addTile(edge, full: photos.count >= PhotoStore.max)
                ForEach(Array(photos.enumerated()), id: \.element) { index, ref in
                    thumb(ref, index, edge)
                }
            }
        }
    }

    private func addTile(_ edge: CGFloat, full: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        let dash: StrokeStyle = StrokeStyle(lineWidth: T.Size.hairline * 1.5, dash: [T.Space.s1, T.Space.s1])
        return PhotoPicker(
            disabled: full,
            onPicked: { (name: String) -> Void in addPhoto(name) },
            onFailed: { store.say("這張照片加不進來，換一張試試。") }
        ) { (busy: Bool) in
            VStack(spacing: T.Space.s1) {
                LineIcon(IconPaths.plus, color: full ? C.textDisabled : C.strong)
                DomyText(
                    busy ? "處理中…" : (full ? "最多 \(PhotoStore.max) 張" : "加照片"), .footnote,
                    tone: full ? .disabled : .strong, lines: 2, align: .center)
            }
            .padding(T.Space.s2)
            .frame(width: edge, height: edge)
            .overlay(shape.strokeBorder(full ? C.fieldBorder : C.strong, style: dash))
            .contentShape(shape)
        }
        .accessibilityLabel(full ? "照片最多 \(PhotoStore.max) 張" : "從相簿加一張照片")
        .accessibilityIdentifier("stop-add-photo")
    }

    private func thumb(_ ref: String, _ index: Int, _ edge: CGFloat) -> some View {
        Button {
            viewing = StopPhotoPick(ref: ref, index: index)
        } label: {
            PhotoThumb(ref: ref, edge: edge)
        }
        .buttonStyle(PressStyle())
        .accessibilityLabel("第 \(index + 1) 張照片，點一下看大圖")
        .accessibilityIdentifier("stop-photo-\(index)")
    }

    /// 看大圖。下面可以刪，刪了提示條上有復原
    private func viewer(_ v: StopPhotoPick) -> some View {
        SheetScaffold("第 \(v.index + 1) 張照片", onClose: { viewing = nil }) {
            PhotoImage(ref: v.ref, fit: true)
                .frame(maxWidth: .infinity, minHeight: T.Size.heroButton)
                .clipShape(RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous))
                .accessibilityLabel("第 \(v.index + 1) 張照片")
            DomyButton("刪掉這張", variant: .destructive, fullWidth: true) {
                let ref: String = v.ref
                viewing = nil
                removePhoto(ref)
            }
            .accessibilityIdentifier("stop-photo-remove")
            DomyText("刪錯了，按提示條上的「復原」就回來。", .footnote, tone: .secondary)
        }
        .presentationDetents([.large])
    }

    /// 照片處理完才叫，中間清單可能變過，所以照現在的清單加
    private func addPhoto(_ ref: String) {
        if patch.moved {
            PhotoStore.removeLater(ref)
            store.say("剛剛換到別趟了，照片沒有加上去。")
            return
        }
        guard let stop = patch.now else {
            PhotoStore.removeLater(ref)
            store.say("這一站不在這趟裡了，照片沒有加上去。")
            return
        }
        if (stop.photos ?? []).count >= PhotoStore.max {
            PhotoStore.removeLater(ref)
            store.say("這一站已經有 \(PhotoStore.max) 張了，這張沒有加上去。")
            return
        }
        Haptic.notify(.success)
        patch.change("加了一張照片。") { (x: inout Stop) -> Void in
            var list: [String] = x.photos ?? []
            list.append(ref)
            x.photos = list
        }
    }

    /// 只拿掉引用，檔案留到下次開 app 才刪，中間都能復原
    private func removePhoto(_ ref: String) {
        guard !patch.moved, let stop = patch.now else { return }
        let old: [String] = stop.photos ?? []
        if !old.contains(ref) { return }
        Haptic.impact(.light)
        patch.change("照片刪掉了。") { (x: inout Stop) -> Void in
            let list: [String] = x.photos ?? []
            x.photos = list.filter { (p: String) -> Bool in p != ref }
        }
        PhotoStore.removeLater(ref)
    }
}

// MARK: - 在這裡花的

/// 這一站記的每一筆（韓元或台幣、可以寫花在哪），和記一筆的那一格。
/// 換算用使用者自己填的匯率，沒填只寫原本的幣別，不上網抓
struct StopSpendBlock: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    let id: String
    let it: Stop
    let trip: Trip
    /// 這一站排在第幾天
    let day: Int

    @State private var amount: String = ""
    @State private var note: String = ""
    @State private var cur: SpendCur = SpendCur.krw
    /// 匯率那一格正在打的字（SpendRateField，PrepCost.swift）
    @State private var rate: String = ""
    @State private var rateBase: String? = nil

    /// 換算用的匯率：匯率正在打、還沒存的，先照打的算
    private var shownRate: Double? {
        guard let base = rateBase, rate != base else { return trip.rate }
        return parseRate(rate)
    }

    /// 出發之後記的才算那一天；出發前記的（先買的票）不寫第幾天
    private var spendDay: Int? {
        guard let phase = store.phase else { return nil }
        if case .plan = phase { return nil }
        return day
    }

    var body: some View {
        let list: [Spend] = stopSpends(trip, id)
        VStack(alignment: .leading, spacing: T.Space.s3) {
            records(list)
            form
        }
    }

    private func footer(_ list: [Spend]) -> String {
        if list.isEmpty {
            return "在這裡花了錢就記一筆，韓元、台幣都可以，一站可以記好幾筆。存在手機裡，沒網路也能記，也會算進「花費」的合計。"
        }
        let sum: SpendSum = spendSum(list, shownRate)
        let mid: String = spendNeedsRate(sum) ? "。還沒填匯率，韓元先不換成台幣" : ""
        return spendSumText(sum) + mid + "。點一筆可以刪掉，刪錯了按「復原」。"
    }

    private func records(_ list: [Spend]) -> some View {
        DomySection("在這裡花的", footer: footer(list)) {
            if list.isEmpty {
                TextRow("還沒有記")
                    .accessibilityIdentifier("stop-spend-empty")
            } else {
                ForEach(list, id: \.id) { (x: Spend) in
                    StopSpendRow(x: x, twd: spendTwdText(x, shownRate)) {
                        removeOne(x)
                    }
                }
            }
        }
    }

    private var form: some View {
        Card {
            FieldLabel("記一筆")
            Segmented(value: cur, options: [(SpendCur.krw, "韓元"), (SpendCur.twd, "台幣")]) { (k: SpendCur) in
                cur = k
            }
            .accessibilityIdentifier("stop-spend-cur")
            amountField
            noteField
            DomyButton("記一筆", variant: .secondary, disabled: parseKrw(amount) == 0, fullWidth: true) {
                addOne()
            }
            .accessibilityIdentifier("stop-spend-add")
            rateBlock
        }
    }

    /// 邊打邊換：韓元、有匯率就寫約多少台幣
    private var amountHelper: String? {
        let typed: Double = parseKrw(amount)
        if cur == SpendCur.twd { return nil }
        if typed == 0 { return "打金額就換算成台幣。真的花了再按「記一筆」。" }
        guard let twd = toTwd(typed, shownRate) else { return "填了下面的匯率，就會換成台幣。" }
        return "約 \(money(twd))，照你填的匯率算"
    }

    private var amountField: some View {
        let krw: Bool = cur == SpendCur.krw
        return DomyTextField(
            krw ? "多少韓元" : "多少台幣", text: $amount, placeholder: krw ? "例如 12000" : "例如 300",
            helper: amountHelper, keyboard: .numberPad
        )
        .accessibilityIdentifier("stop-spend-amount")
        .onChange(of: amount) { (_: String, text: String) in
            if text.count > 9 {
                amount = String(text.prefix(9))
            }
        }
    }

    private var noteField: some View {
        DomyTextField("花在哪（可以不填）", text: $note, placeholder: "例如：門票、紀念品")
            .accessibilityIdentifier("stop-spend-note")
            .onChange(of: note) { (_: String, text: String) in
                if text.count > 30 {
                    note = String(text.prefix(30))
                }
            }
    }

    /// 沒填匯率：在這裡就能填（跟花費頁同一格）。填了：寫照哪個匯率算，要改去花費頁
    @ViewBuilder
    private var rateBlock: some View {
        if let r = trip.rate, r != 0, rateBase == nil || rate == rateBase {
            DomyText("照你填的匯率換算：\(rateWords(r))。要改匯率、看整趟花了多少，到「花費」。", .footnote, tone: .secondary)
            DomyButton("到花費", variant: .plain, size: .compact) {
                nav.push(.cost)
            }
            .accessibilityIdentifier("stop-spend-cost")
        } else {
            SpendRateField(text: $rate, base: $rateBase, testId: "stop-spend-rate")
        }
    }

    private func addOne() {
        let typed: Double = parseKrw(amount)
        if typed == 0 { return }
        let stopId: String = id
        // 這一站剛被拿掉、換掉了就不記，免得記到不在的站。打的字留著，還來得及到花費頁記
        let here: Bool = store.s.trip.flatMap { (t: Trip) -> Found? in findItem(t, stopId) } != nil
        if !here {
            store.say("這一站不在這趟裡了，這一筆沒有記。")
            return
        }
        Haptic.notify(.success)
        let memo: String = note
        let kind: SpendCur = cur
        let name: String = it.n
        let when: Int? = spendDay
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let x = addSpend(&trip, typed, memo, when, cur: kind, stopId: stopId, stopName: name) else {
                return nil
            }
            d.trip = trip
            return "在「\(name)」記了 \(spendAmountText(x))。"
        }
        amount = ""
        note = ""
    }

    private func removeOne(_ x: Spend) {
        Haptic.impact(.light)
        let spendId: String = x.id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let gone = removeSpend(&trip, spendId) else { return nil }
            d.trip = trip
            return "刪掉「\(gone.note ?? spendAmountText(gone))」這一筆了。"
        }
    }
}

/// 在這裡花的一筆：點一下刪掉
private struct StopSpendRow: View {
    let x: Spend
    let twd: String?
    let onDelete: () -> Void

    private var title: String {
        return x.note ?? "沒寫花在哪"
    }

    private var sub: String? {
        var bits: [String] = []
        if let day = x.day, day != 0 { bits.append("第 \(day) 天") }
        if x.cur == SpendCur.twd { bits.append("台幣") }
        return bits.isEmpty ? nil : bits.joined(separator: "・")
    }

    var body: some View {
        Button(action: onDelete) {
            TextRow(title, note: sub) {
                VStack(alignment: .trailing, spacing: 0) {
                    DomyText(spendAmountText(x), .headline)
                    if let twd {
                        DomyText(twd, .footnote, tone: .secondary)
                    }
                }
            }
            .padding(.horizontal, T.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)，\(spendAmountText(x))，點一下刪掉")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("stop-spend-row-\(x.id)")
    }
}
