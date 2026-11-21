// 一趟「去過的」：每一天去了哪、寫的那一句、照片。可以做成一頁有地圖的網頁檔傳給朋友。
// 現在這趟的站點一下會打開那一站；已經收起來的旅行點一下在這張卡裡直接補。兩邊都可以補一句、加照片。
// 對應 mobile/src/sheets/AlbumSheet.tsx。AlbumSource 定義在 App/Sheets.swift。
import SwiftUI

/// 那一天的日期，已經排好版的字。沒有出發日或不知道第幾天就沒有
private func albumDateOf(_ start: String?, _ day: Int?) -> String? {
    guard let start = start, !start.isEmpty, let day = day, day != 0 else { return nil }
    return fmtDay(addDays(start, day - 1))
}

/// 做網頁檔：照片讀成資料網址包進去，存成暫存檔。做不成回 nil。會讀檔，不要在主執行緒叫
private func albumFile(_ items: [BasketItem], _ title: String, _ dates: String, _ start: String?) -> URL? {
    var stops: [AlbumStop] = []
    for it in items {
        var photos: [String] = []
        for ref in it.photos ?? [] {
            if let uri = PhotoStore.dataUri(ref) { photos.append(uri) }
        }
        stops.append(
            AlbumStop(
                n: it.n, kr: it.kr, day: it.day, date: albumDateOf(start, it.day), say: it.say,
                lat: it.lat, lng: it.lng, photos: photos))
    }
    let html: String = albumHtml(Album(title: title, dates: dates, stops: stops))
    return PhotoStore.writeTemp("radish-trip.html", html)
}

/// 清單裡的一站：圖示、名字、那一句、照片
private struct AlbumRow: View {
    let it: BasketItem
    let onTap: () -> Void

    var body: some View {
        let say: String = it.say ?? ""
        let photos: [String] = it.photos ?? []
        // 上半（圖示與字）是一顆按鈕，按下整列變灰；照片條放在按鈕外面，才能左右滑
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onTap) {
                HStack(spacing: T.Space.s3) {
                    CatIcon(it)
                    VStack(alignment: .leading, spacing: T.Space.s1 / 2) {
                        DomyText(it.n, .headline)
                        DomyText(
                            say.isEmpty ? "點一下可以寫一句、加照片" : "「\(say)」", .subheadline, tone: .secondary)
                    }
                    .fillLeading()
                }
                .padding(.vertical, T.Space.s3)
                .padding(.horizontal, T.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(RowPressStyle())
            .padding(.horizontal, -T.Space.s4)
            .accessibilityHint("寫一句、加照片")
            if !photos.isEmpty {
                PhotoStrip(refs: photos)
                    .padding(.bottom, T.Space.s3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AlbumSheet: View {
    let source: AlbumSource
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets
    @State private var busy: Bool = false
    /// 已經收起來的旅行：正在補哪一站（第幾個）
    @State private var edit: Int? = nil
    @State private var share: ShareItem? = nil

    init(source: AlbumSource) {
        self.source = source
    }

    private var basket: Basket? {
        switch source {
        case .current:
            return nil
        case .basket(let id):
            return store.s.baskets.first { (b: Basket) -> Bool in b.id == id }
        }
    }

    private var trip: Trip? {
        switch source {
        case .current:
            return store.s.trip
        case .basket:
            return nil
        }
    }

    private var title: String {
        if let basket = basket { return basket.title }
        if let trip = trip { return tripTitle(trip) }
        return ""
    }

    private var start: String? {
        if let basket = basket { return basket.start }
        return trip?.start
    }

    private var days: Int? {
        if let basket = basket { return basket.days }
        return trip?.days
    }

    private var items: [BasketItem] {
        if let basket = basket { return basket.items }
        if let trip = trip { return visitedOf(trip) }
        return []
    }

    private var dates: String {
        guard let start = start, !start.isEmpty, let days = days, days != 0 else { return "" }
        return "\(fmtDay(start))–\(fmtDay(addDays(start, days - 1)))"
    }

    private func dateOf(_ day: Int?) -> String? {
        return albumDateOf(start, day)
    }

    /// 正在補的那一站。不是已經收起來的旅行、沒在補、或位置對不上就是 nil
    private var editing: (basket: Basket, index: Int, item: BasketItem)? {
        guard let basket = basket, let index = edit else { return nil }
        guard index >= 0 && index < basket.items.count else { return nil }
        return (basket: basket, index: index, item: basket.items[index])
    }

    var body: some View {
        Group {
            if let x = editing {
                editSheet(x.basket, x.index, x.item)
            } else {
                listSheet
            }
        }
        .sheet(item: $share) { (item: ShareItem) in
            ShareSheet(items: item.items)
        }
    }

    /* ---------- 已經收起來的旅行：補一句、加照片 ---------- */

    @MainActor
    private func patch(_ basketId: String, _ index: Int, _ change: (inout BasketItem) -> Void) {
        store.mutate { (d: inout AppState) -> Void in
            _ = updateBasketItem(&d, basketId, index, change)
        }
    }

    private func editHead(_ item: BasketItem) -> String {
        var out: String = title
        if let day = item.day, day != 0 {
            out += "・第 \(day) 天"
            if let date = dateOf(day) { out += " " + date }
        }
        return out
    }

    private func editSheet(_ basket: Basket, _ index: Int, _ item: BasketItem) -> some View {
        let basketId: String = basket.id
        return SheetScaffold(item.n, onClose: { edit = nil }) {
            DomyText(editHead(item), .subheadline, tone: .secondary)
            VisitNote(
                say: item.say,
                photos: item.photos ?? [],
                onSay: { (text: String) -> Void in
                    patch(basketId, index) { (x: inout BasketItem) -> Void in x.say = text }
                },
                onPhotos: { (next: [String]) -> Void in
                    patch(basketId, index) { (x: inout BasketItem) -> Void in x.photos = next }
                })
            DomyButton("好了", fullWidth: true) { edit = nil }
                .accessibilityIdentifier("album-edit-done")
        }
    }

    /* ---------- 清單 ---------- */

    private var listSheet: some View {
        let list: [BasketItem] = items
        return SheetScaffold(title.isEmpty ? "去過的" : title, onClose: { sheets.close() }) {
            if list.isEmpty {
                DomyEmptyState(
                    icon: IconPaths.tabTrips, title: "這趟還沒有去過的地方",
                    message: "旅途中每去過一站，按「去過了，拔起來」，它就會出現在這裡。")
            } else {
                DomyText(countLine(list.count), .subheadline, tone: .secondary)
                groupList(list)
                DomyButton(busy ? "正在做網頁檔…" : "做成地圖網頁，傳給朋友", disabled: busy, fullWidth: true) {
                    makeShare()
                }
                .accessibilityIdentifier("album-share")
                DomyText(
                    "會做成一個網頁檔，上面是這趟的地圖，下面是每一站的那一句和照片，照片都包在檔案裡。朋友用瀏覽器就能開。有網路時地圖是可以縮放的真地圖，沒網路時是一張簡單的路線圖。照片多的話檔案會比較大。",
                    .footnote, tone: .secondary)
            }
        }
    }

    private func countLine(_ count: Int) -> String {
        let when: String = dates
        let head: String = when.isEmpty ? "" : when + "・"
        return head + "去了 \(count) 個地方"
    }

    /// 有哪幾天（沒記第幾天的算第 0 組，排最前面、沒有標題）
    private func groupsOf(_ list: [BasketItem]) -> [Int] {
        let all: [Int] = list.map { (it: BasketItem) -> Int in it.day ?? 0 }
        return Array(Set(all)).sorted()
    }

    private func groupTitle(_ g: Int) -> String? {
        if g == 0 { return nil }
        var out: String = "第 \(g) 天"
        if let date = dateOf(g) { out += "　" + date }
        return out
    }

    /// 這一天的站，連同它在整份清單裡是第幾個
    private func rowsOf(_ list: [BasketItem], _ g: Int) -> [(i: Int, it: BasketItem)] {
        var out: [(i: Int, it: BasketItem)] = []
        for (i, it) in list.enumerated() {
            if (it.day ?? 0) == g { out.append((i: i, it: it)) }
        }
        return out
    }

    private func groupList(_ list: [BasketItem]) -> some View {
        ForEach(groupsOf(list), id: \.self) { (g: Int) in
            DomySection(groupTitle(g)) {
                ForEach(rowsOf(list, g), id: \.i) { (row: (i: Int, it: BasketItem)) in
                    AlbumRow(it: row.it) { tap(row.i, row.it) }
                        .accessibilityIdentifier("album-item-\(row.i)")
                }
            }
        }
    }

    @MainActor
    private func tap(_ index: Int, _ it: BasketItem) {
        if basket != nil {
            edit = index
        } else if let id = it.id, !id.isEmpty {
            sheets.open(.stop(id: id))
        }
    }

    /* ---------- 做成網頁檔分享 ---------- */

    @MainActor
    private func makeShare() {
        if busy { return }
        busy = true
        let list: [BasketItem] = items
        let name: String = title
        let when: String = dates
        let from: String? = start
        Task { @MainActor in
            let work: Task<URL?, Never> = Task.detached(priority: .userInitiated) { () -> URL? in
                return albumFile(list, name, when, from)
            }
            let url: URL? = await work.value
            busy = false
            if let url = url {
                share = ShareItem(items: [url])
            } else {
                store.say("網頁檔沒做成功，等一下再試一次。")
            }
        }
    }
}
