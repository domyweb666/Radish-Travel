// 去過的那一趟（S20，線框 .uiux/03-線框/線框/A16-Visited.dc.html）：推進頁。
// 最上面是做成地圖網頁、傳給朋友；下面一次看一天，每站有寫的那一句和照片。
// 現在這趟的站點一下推進到那一站（StopScreen）；已經收起來的旅行，StopScreen 找不到那一站
// （它只看現在這趟），所以點一下在這一頁升起半頁直接補一句、加照片。
// 原本是彈出卡 AlbumSheet（對應 mobile/src/sheets/AlbumSheet.tsx），五天一路往下捲；線框改成一次看一天。
// AlbumSource 定義在 App/Sheets.swift。
import SwiftUI

/* ---------- 一趟去過的：現在這趟和收起來的共用 ---------- */

/// 一趟去過的站和它的標題、日期。收起來的那一趟有 basketId
struct VisitedTrip: Sendable {
    let title: String
    let start: String?
    let days: Int?
    let items: [BasketItem]
    let basketId: String?

    /// 12/16（三） – 12/20（日）。沒有出發日就是空字串
    var dates: String {
        guard let start, !start.isEmpty, let days, days != 0 else { return "" }
        return "\(fmtDay(start)) – \(fmtDay(addDays(start, days - 1)))"
    }

    /// 第幾天的日期，已經排好版的字。沒有出發日或不知道第幾天就沒有
    func dateOf(_ day: Int?) -> String? {
        guard let start, !start.isEmpty, let day, day != 0 else { return nil }
        return fmtDay(addDays(start, day - 1))
    }
}

/// 照來源找那一趟。現在這趟已經收起來、或那一趟找不到就是 nil
func visitedTrip(_ s: AppState, _ source: AlbumSource) -> VisitedTrip? {
    switch source {
    case .current:
        guard let trip = s.trip else { return nil }
        return VisitedTrip(
            title: tripTitle(trip), start: trip.start, days: trip.days, items: visitedOf(trip), basketId: nil)
    case .basket(let id):
        guard let b = s.baskets.first(where: { (x: Basket) -> Bool in x.id == id }) else { return nil }
        return VisitedTrip(title: b.title, start: b.start, days: b.days, items: b.items, basketId: b.id)
    }
}

/// 做網頁檔：照片讀成資料網址包進去，存成暫存檔。做不成回 nil。會讀檔，不要在主執行緒叫
private func albumFile(_ v: VisitedTrip) -> URL? {
    var stops: [AlbumStop] = []
    for it in v.items {
        var photos: [String] = []
        for ref in it.photos ?? [] {
            if let uri = PhotoStore.dataUri(ref) { photos.append(uri) }
        }
        stops.append(
            AlbumStop(
                n: it.n, kr: it.kr, day: it.day, date: v.dateOf(it.day), say: it.say,
                lat: it.lat, lng: it.lng, photos: photos))
    }
    let html: String = albumHtml(Album(title: v.title, dates: v.dates, stops: stops))
    return PhotoStore.writeTemp("radish-trip.html", html)
}

/// 在背景做網頁檔，做好回來。這一頁和回來後那張卡（TripCards.swift 的 DoneCard）共用
func makeAlbumFile(_ v: VisitedTrip) async -> URL? {
    let work: Task<URL?, Never> = Task.detached(priority: .userInitiated) { () -> URL? in
        return albumFile(v)
    }
    return await work.value
}

/* ---------- 一站的列 ---------- */

/// 清單裡的一站：圖示、名字、那一句、照片。onTap 是 nil 就不給點
private struct VisitedRow: View {
    let it: BasketItem
    let onTap: (() -> Void)?

    private var line: String {
        let say: String = it.say ?? ""
        if !say.isEmpty { return "「\(say)」" }
        return onTap == nil ? "沒有寫那一句" : "點一下可以寫一句、加照片"
    }

    private var head: some View {
        HStack(spacing: T.Space.s3) {
            CatIcon(it)
            VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
                DomyText(it.n, .headline)
                DomyText(line, .subheadline, tone: .secondary)
            }
            .fillLeading()
        }
        .padding(.vertical, T.Space.s3)
        .padding(.horizontal, T.Space.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    var body: some View {
        let photos: [String] = it.photos ?? []
        // 上半（圖示與字）是一顆按鈕，按下整列變灰；照片條放在按鈕外面，才能左右滑
        VStack(alignment: .leading, spacing: 0) {
            if let onTap {
                Button(action: onTap) { head }
                    .buttonStyle(RowPressStyle())
                    .padding(.horizontal, -T.Space.s4)
                    .accessibilityHint("寫一句、加照片")
            } else {
                head
                    .padding(.horizontal, -T.Space.s4)
                    .accessibilityElement(children: .combine)
            }
            if !photos.isEmpty {
                PhotoStrip(refs: photos)
                    .padding(.bottom, T.Space.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 換天那一排：跟這趟的每天分頁長得一樣（TripScreenParts.swift 的 TripDayTabs），只是不看 Trip
private struct VisitedDayTabs: View {
    let groups: [Int]
    let value: Int
    let dateOf: (Int) -> String?
    let onChange: (Int) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: T.Space.s2) {
                ForEach(groups, id: \.self) { (g: Int) in
                    tab(g)
                }
            }
            .padding(.horizontal, T.Size.screenMargin)
        }
        .padding(.horizontal, -T.Size.screenMargin)
    }

    private func tab(_ g: Int) -> some View {
        let on: Bool = g == value
        let name: String = g == 0 ? "沒記哪天" : "第 \(g) 天"
        let date: String = dateOf(g) ?? ""
        return Button {
            onChange(g)
        } label: {
            VStack(spacing: 0) {
                DomyText(name, .callout, tone: on ? .onAccent : .primary)
                if !date.isEmpty {
                    DomyText(date, .caption, tone: on ? .onAccent : .secondary)
                }
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
        .accessibilityLabel(date.isEmpty ? name : "\(name)，\(date)")
        .accessibilityAddTraits(on ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier("visited-day-\(g)")
    }
}

/* ---------- 收起來的那一趟：補一句、加照片 ---------- */

/// 收起來的那一趟正在補哪一站（在那一趟清單裡是第幾個）
private struct BasketEdit: Identifiable {
    let index: Int
    var id: Int { index }
}

/// 半頁：補一句、加照片。從 store 現讀那一站，改了直接寫回去
private struct BasketEditSheet: View {
    @Environment(AppStore.self) private var store
    let basketId: String
    let index: Int
    let onClose: () -> Void

    // 有 private 的環境值，自動產生的 init 會變成 private，所以自己寫一個
    init(basketId: String, index: Int, onClose: @escaping () -> Void) {
        self.basketId = basketId
        self.index = index
        self.onClose = onClose
    }

    private var found: (v: VisitedTrip, item: BasketItem)? {
        guard let v = visitedTrip(store.s, .basket(id: basketId)) else { return nil }
        guard index >= 0 && index < v.items.count else { return nil }
        return (v: v, item: v.items[index])
    }

    private func head(_ v: VisitedTrip, _ item: BasketItem) -> String {
        var out: String = v.title
        if let day = item.day, day != 0 {
            out += "・第 \(day) 天"
            if let date = v.dateOf(day) { out += " " + date }
        }
        return out
    }

    private func patch(_ change: (inout BasketItem) -> Void) {
        let id: String = basketId
        let at: Int = index
        store.mutate { (d: inout AppState) -> Void in
            _ = updateBasketItem(&d, id, at, change)
        }
    }

    var body: some View {
        if let x = found {
            SheetScaffold(x.item.n, onClose: onClose) {
                DomyText(head(x.v, x.item), .subheadline, tone: .secondary)
                VisitNote(
                    say: x.item.say,
                    photos: x.item.photos ?? [],
                    onSay: { (text: String) -> Void in
                        patch { (it: inout BasketItem) -> Void in it.say = text }
                    },
                    onPhotos: { (next: [String]) -> Void in
                        patch { (it: inout BasketItem) -> Void in it.photos = next }
                    })
                DomyButton("好了", fullWidth: true, action: onClose)
                    .accessibilityIdentifier("album-edit-done")
            }
        } else {
            SheetScaffold("找不到這一站", onClose: onClose) {
                DomyText("這一站可能已經不在這一趟裡了。", .subheadline, tone: .secondary)
            }
        }
    }
}

/* ---------- 這一頁 ---------- */

struct VisitedScreen: View {
    let source: AlbumSource
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    /// 點了哪一天。還沒點就是旅途中的今天，或第一個有去過的那天
    @State private var picked: Int? = nil
    @State private var busy: Bool = false
    @State private var share: ShareItem? = nil
    @State private var edit: BasketEdit? = nil

    init(source: AlbumSource) {
        self.source = source
    }

    var body: some View {
        Group {
            if let v = visitedTrip(store.s, source) {
                page(v)
            } else {
                Screen("去過的") {
                    DomyEmptyState(
                        icon: IconPaths.tabTrips, title: "找不到這一趟",
                        message: "這一趟可能已經收起來了，到「旅行」的去過的旅行找找看。")
                }
            }
        }
        .sheet(item: $share) { (item: ShareItem) in
            ShareSheet(items: item.items)
        }
    }

    private func page(_ v: VisitedTrip) -> some View {
        Screen(v.title) {
            DomyText(subtitle(v), .subheadline, tone: .secondary)
                .padding(.top, -T.Space.s4)
            if v.items.isEmpty {
                DomyEmptyState(
                    icon: IconPaths.tabTrips, title: "這趟還沒有去過的地方",
                    message: "旅途中每去過一站，按「去過了，拔起來」，它就會出現在這裡。")
            } else {
                shareBlock(v)
                dayBlock(v)
            }
        }
        .sheet(item: $edit) { (e: BasketEdit) in
            BasketEditSheet(basketId: v.basketId ?? "", index: e.index, onClose: { edit = nil })
                .environment(store)
                .environment(nav)
                .tint(C.accent)
        }
    }

    private func subtitle(_ v: VisitedTrip) -> String {
        let when: String = v.dates
        let head: String = when.isEmpty ? "" : when + "・"
        return head + "去了 \(v.items.count) 個地方"
    }

    private func shareNote(_ v: VisitedTrip) -> String {
        let note: String = "會做成一個網頁檔：上面是這趟的地圖，下面是每一站的那一句和照片。朋友用瀏覽器就能開。"
        let photos: Int = v.items.reduce(0) { (n: Int, it: BasketItem) -> Int in n + (it.photos?.count ?? 0) }
        return photos > 0 ? note + "照片都包在檔案裡，照片多的話檔案會比較大。" : note
    }

    private func shareBlock(_ v: VisitedTrip) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyButton(busy ? "正在做網頁檔…" : "做成地圖網頁，傳給朋友", disabled: busy, fullWidth: true) {
                makeShare(v)
            }
            .accessibilityIdentifier("album-share")
            DomyText(shareNote(v), .footnote, tone: .secondary)
        }
    }

    /* ---------- 一次看一天 ---------- */

    /// 有哪幾天：出發到回來每一天都列（跟這趟的分頁一樣），沒記第幾天的放最後一格
    private func groupsOf(_ v: VisitedTrip) -> [Int] {
        let itemDays: [Int] = v.items.map { (it: BasketItem) -> Int in it.day ?? 0 }
        let last: Int = max(v.days ?? 0, itemDays.max() ?? 0)
        var out: [Int] = last >= 1 ? Array(1...last) : []
        if itemDays.contains(0) { out.append(0) }
        return out
    }

    /// 現在看的那一天
    private func shownOf(_ v: VisitedTrip, _ groups: [Int]) -> Int {
        if let p = picked, groups.contains(p) { return p }
        if v.basketId == nil, case .trip(let today)? = store.phase, groups.contains(today) {
            let has: Bool = v.items.contains { (it: BasketItem) -> Bool in it.day == today }
            if has { return today }
        }
        for g in groups {
            let has: Bool = v.items.contains { (it: BasketItem) -> Bool in (it.day ?? 0) == g }
            if has { return g }
        }
        return groups.first ?? 1
    }

    /// 這一天的站，連同它在整份清單裡是第幾個（收起來的那一趟改的時候要用）
    private func rowsOf(_ v: VisitedTrip, _ g: Int) -> [(i: Int, it: BasketItem)] {
        var out: [(i: Int, it: BasketItem)] = []
        for (i, it) in v.items.enumerated() where (it.day ?? 0) == g {
            out.append((i: i, it: it))
        }
        return out
    }

    private func dayBlock(_ v: VisitedTrip) -> some View {
        let groups: [Int] = groupsOf(v)
        let shown: Int = shownOf(v, groups)
        let rows: [(i: Int, it: BasketItem)] = rowsOf(v, shown)
        return VStack(alignment: .leading, spacing: T.Space.s3) {
            VisitedDayTabs(
                groups: groups, value: shown, dateOf: { (g: Int) -> String? in v.dateOf(g) },
                onChange: { (g: Int) in picked = g })
            if rows.isEmpty {
                Card {
                    DomyText(emptyDay(v), .subheadline, tone: .secondary)
                }
            } else {
                DomySection {
                    ForEach(rows, id: \.i) { (row: (i: Int, it: BasketItem)) in
                        VisitedRow(it: row.it, onTap: tapOf(v, row.i, row.it))
                            .accessibilityIdentifier("album-item-\(row.i)")
                    }
                }
            }
        }
    }

    private func emptyDay(_ v: VisitedTrip) -> String {
        if v.basketId == nil {
            return "這一天還沒有按過「去過了」的站。有去過但沒按到的，在「這趟」點那一站可以補。"
        }
        return "這一天沒有記到去過的站。"
    }

    /// 點了做什麼：現在這趟推進到那一站；收起來的那一趟在這一頁補；都不行就不給點
    private func tapOf(_ v: VisitedTrip, _ index: Int, _ it: BasketItem) -> (() -> Void)? {
        if v.basketId != nil {
            return { edit = BasketEdit(index: index) }
        }
        guard let id = it.id, !id.isEmpty else { return nil }
        guard let trip = store.s.trip, findItem(trip, id) != nil else { return nil }
        return { nav.push(.stop(id: id)) }
    }

    /* ---------- 做成網頁檔分享 ---------- */

    private func makeShare(_ v: VisitedTrip) {
        if busy { return }
        busy = true
        Task { @MainActor in
            let url: URL? = await makeAlbumFile(v)
            busy = false
            if let url {
                share = ShareItem(items: [url])
            } else {
                store.say("網頁檔沒做成功，等一下再試一次。")
            }
        }
    }
}
