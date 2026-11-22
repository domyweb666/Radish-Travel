// 這一天的路線（S12，線框 A8）：地圖、每一段怎麼去、路上大約幾分鐘（估），最下面一顆「請 AI 提一個改法」。
// 半頁，可以拉到全高。分鐘數照 Plan.swift 的 dayLegs，總數含從住的地方出發和回去（跟這一天清單加總的方式一樣）。
// AI 的改法要在同一張換一面（「這次會改」），等 AI 回覆的格式定了再做；現在按了是送出那一句，升起「剛剛那一則」。
// 原本對應 mobile/src/sheets/MapSheet.tsx（看這天的地圖），2026-11-23 照 A 版線框改。
import SwiftUI

/// legs[i]，超出範圍就當成不明
private func mapLegAt(_ legs: [Leg?], _ i: Int) -> Leg? {
    guard i >= 0 && i < legs.count else { return nil }
    return legs[i]
}

/// 路線的一段：從哪到哪、怎麼去
private struct RouteLeg: Identifiable {
    let id: Int
    let title: String
    let note: String
}

/// 住的地方 → 1 → 2 → … → 住的地方。號碼跟地圖上的標記一樣
private func routeLegs(_ h: HotelPt, _ stops: [Stop], _ legs: [Leg?]) -> [RouteLeg] {
    let home: String = "\(h.n)（住的地方）"
    var out: [RouteLeg] = []
    for i in 0...stops.count {
        let from: String = i == 0 ? home : "\(i) \(stops[i - 1].n)"
        let to: String = i == stops.count ? home : "\(i + 1) \(stops[i].n)"
        out.append(RouteLeg(id: i, title: "\(from) → \(to)", note: legText(mapLegAt(legs, i))))
    }
    return out
}

/// 路上大約幾分鐘（估）。距離不明的那幾段沒算進去，要講出來
private func routeTotal(_ legs: [Leg?]) -> String {
    var total: Int = 0
    var unknown: Int = 0
    for l in legs {
        if let l {
            total += l.min
        } else {
            unknown += 1
        }
    }
    var out: String = "\(legs.count) 段・路上大約 \(total) 分鐘（估），含從住的地方出發和回去"
    if unknown > 0 {
        out += "。有 \(unknown) 段距離不明，沒算進去"
    }
    return out
}

struct MapSheet: View {
    let day: Int
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets

    init(day: Int) {
        self.day = day
    }

    var body: some View {
        SheetScaffold("第 \(day) 天的路線", onClose: { sheets.close() }) {
            if let trip = store.s.trip {
                content(trip)
            } else {
                DomyText("現在沒有這趟。", .body, tone: .secondary)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func stopsOf(_ trip: Trip) -> [Stop] {
        return dayStops(trip, day).map { (x: Found) -> Stop in x.it }
    }

    /// 地圖上的點：住的地方，再來是有座標的站。號碼照這天第幾站，沒座標的站跳過但號碼不重排
    private func pointsOf(_ h: HotelPt, _ stops: [Stop]) -> [MapPoint] {
        var out: [MapPoint] = [
            MapPoint(key: "home", title: "住的地方（\(h.n)）", subtitle: h.kr, lat: h.lat, lng: h.lng, home: true)
        ]
        for (i, it) in stops.enumerated() {
            if let lat = it.lat, let lng = it.lng {
                out.append(MapPoint(key: it.id, title: it.n, subtitle: it.kr, lat: lat, lng: lng, num: i + 1))
            }
        }
        return out
    }

    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        let h: HotelPt = hotelPt(store.s.settings, trip)
        let stops: [Stop] = stopsOf(trip)
        let legs: [Leg?] = dayLegs(trip, store.s.settings, day)
        DomyText("\(fmtDay(addDays(trip.start, day - 1)))・從\(h.n)出發，回到\(h.n)", .footnote, tone: .secondary)
        if stops.isEmpty {
            DomyText("這天沒有排站。", .body, tone: .secondary)
        } else {
            VStack(alignment: .leading, spacing: T.Space.s2) {
                DayMap(points: pointsOf(h, stops), compact: true)
                DomyText("底圖要網路，沒網路時地圖上只剩點，下面每一段照樣看得到。", .caption, tone: .secondary)
            }
            DomyText(routeTotal(legs), .subheadline, numeric: true)
                .accessibilityIdentifier("route-total")
            legSection(routeLegs(h, stops, legs))
            askButton
        }
    }

    private func legSection(_ rows: [RouteLeg]) -> some View {
        DomySection(footer: "手機算的，沒有問 AI：照直線距離加三成估，沒有查路線。真的要走的時候，從每一站跳去 Naver 地圖。") {
            ForEach(rows) { (row: RouteLeg) in
                TextRow(row.title, note: row.note)
            }
        }
    }

    private var askButton: some View {
        DomyButton("請 AI 提一個改法", variant: .secondary, fullWidth: true) {
            askAI()
        }
        .accessibilityIdentifier("route-ask")
    }

    /// 送出那一句給 AI，在看的是這一天；回覆從下面升起（剛剛那一則）
    private func askAI() {
        store.talk("幫我看第 \(day) 天的路線，提一個更順路的改法", target: .day(day))
        sheets.open(.reply)
    }
}
