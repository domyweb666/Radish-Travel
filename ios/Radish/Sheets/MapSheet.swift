// 一天的地圖：住的地方＋這天每一站，下面是站與站之間怎麼去。
// 對應 mobile/src/sheets/MapSheet.tsx。
import SwiftUI

/// legs[i]，超出範圍就當成不明
private func mapLegAt(_ legs: [Leg?], _ i: Int) -> Leg? {
    guard i >= 0 && i < legs.count else { return nil }
    return legs[i]
}

struct MapSheet: View {
    let day: Int
    @Environment(AppStore.self) private var store
    @Environment(Sheets.self) private var sheets

    init(day: Int) {
        self.day = day
    }

    var body: some View {
        if let trip = store.s.trip {
            card(trip)
        }
    }

    private func stopsOf(_ trip: Trip) -> [Stop] {
        return dayStops(trip, day).map { (x: Found) -> Stop in x.it }
    }

    private func pointsOf(_ h: HotelPt, _ stops: [Stop]) -> [MapPoint] {
        var out: [MapPoint] = [
            MapPoint(key: "home", title: "住的地方（\(h.n)）", subtitle: h.kr, lat: h.lat, lng: h.lng, home: true)
        ]
        for it in stops {
            if let lat = it.lat, let lng = it.lng {
                out.append(MapPoint(key: it.id, title: it.n, subtitle: it.kr, lat: lat, lng: lng))
            }
        }
        return out
    }

    private func card(_ trip: Trip) -> some View {
        let h: HotelPt = hotelPt(store.s.settings, trip)
        let stops: [Stop] = stopsOf(trip)
        let legs: [Leg?] = dayLegs(trip, store.s.settings, day)
        let title: String = "第 \(day) 天 \(fmtDay(addDays(trip.start, day - 1)))"
        return SheetScaffold(title, onClose: { sheets.close() }) {
            if stops.isEmpty {
                DomyText("這天沒有排站。", .body, tone: .secondary)
            } else {
                DayMap(points: pointsOf(h, stops))
                legSection(h, stops, legs)
            }
        }
    }

    /// 到第 i 站的那一段怎麼去。第一站前面多一句「從住的地方出發」
    private func legNote(_ i: Int, _ legs: [Leg?]) -> String {
        let head: String = i == 0 ? "從住的地方出發・" : ""
        return head + legText(mapLegAt(legs, i))
    }

    private func legSection(_ h: HotelPt, _ stops: [Stop], _ legs: [Leg?]) -> some View {
        DomySection(footer: "點的位置是大概的，距離是直線加三成、時間是估的。真的要走的時候，從每一站的卡跳去 Naver 地圖。") {
            ForEach(Array(stops.enumerated()), id: \.element.id) { i, it in
                TextRow("\(i + 1). \(it.n)", note: legNote(i, legs))
            }
            TextRow("回住的地方（\(h.n)）", note: legText(mapLegAt(legs, legs.count - 1)))
        }
    }
}
