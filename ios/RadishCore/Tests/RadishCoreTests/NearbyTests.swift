// 附近還有什麼（S10，線框 A12）的規則測試：從哪裡算、照距離排、怎麼去、排進哪個時段。
// iOS 版才有，mobile/tests/ 沒有對應的。例子照線框 A12：從益善洞韓屋巷算。
import XCTest

@testable import RadishCore

private func nearbyPlace(_ name: String) throws -> Place {
    return try XCTUnwrap(PLACES.first { (p: Place) -> Bool in p.n == name }, "資料包裡沒有「\(name)」")
}

private func nearbyStop(_ name: String, pulled: Bool = false) throws -> Stop {
    var it: Stop = try planToStop(nearbyPlace(name), "測試")
    if pulled { it.status = .pulled }
    return it
}

/// 一天的行程：上午、下午、晚上各放幾站。offAm 為 true 時上午在路上
private func nearbyTrip(am: [Stop], pm: [Stop], eve: [Stop], offAm: Bool = false) -> Trip {
    let slots: [Slot] = [
        Slot(day: 1, part: .am, off: offAm ? true : nil, items: am),
        Slot(day: 1, part: .pm, items: pm),
        Slot(day: 1, part: .eve, items: eve),
    ]
    return Trip(start: "2026-12-16", days: 1, arrive: .am, leave: .eve, people: 2, slots: slots)
}

/// 線框 A12 那一天：景福宮拔過了，下一站是益善洞韓屋巷，下午還有仁寺洞街，晚上廣藏市場
private func a12Trip() throws -> Trip {
    return try nearbyTrip(
        am: [nearbyStop("景福宮", pulled: true)],
        pm: [nearbyStop("益善洞韓屋巷"), nearbyStop("仁寺洞街")],
        eve: [nearbyStop("廣藏市場")]
    )
}

final class NearbyTests: XCTestCase {
    func test起點是這一天還沒拔的下一站() throws {
        let t: Trip = try a12Trip()
        let o: NearbyOrigin = nearbyOrigin(t, defaultSettings(), 1)
        XCTAssertEqual(o.from, .next)
        XCTAssertEqual(o.name, "益善洞韓屋巷")
        XCTAssertEqual(o.part, .pm)
        XCTAssertTrue(o.known)
    }

    func test都拔完了從最後一站算_沒排站從住的地方算() throws {
        let done: Trip = try nearbyTrip(
            am: [nearbyStop("景福宮", pulled: true)], pm: [nearbyStop("仁寺洞街", pulled: true)], eve: [])
        let o: NearbyOrigin = nearbyOrigin(done, defaultSettings(), 1)
        XCTAssertEqual(o.from, .pulled)
        XCTAssertEqual(o.name, "仁寺洞街")

        let empty: Trip = nearbyTrip(am: [], pm: [], eve: [])
        let home: NearbyOrigin = nearbyOrigin(empty, defaultSettings(), 1)
        XCTAssertEqual(home.from, .home)
        XCTAssertNil(home.stopId)
        XCTAssertTrue(home.name.hasPrefix("住的地方"), home.name)
        XCTAssertTrue(home.known)
        XCTAssertFalse(nearbyRanked(empty, defaultSettings(), 1).isEmpty, "從住的地方也算得出附近")
    }

    func test照距離排_跳過這趟已經排的_線框那三個() throws {
        let t: Trip = try a12Trip()
        let st: Settings = defaultSettings()
        let ranked: [NearbyPick] = nearbyRanked(t, st, 1)
        let used: Set<String> = usedIds(t)
        XCTAssertFalse(ranked.isEmpty)
        for (i, x) in ranked.enumerated() {
            XCTAssertFalse(used.contains(x.place.id), "「\(x.place.n)」已經排了")
            XCTAssertTrue(x.leg.km <= NEARBY_MAX_KM, "「\(x.place.n)」太遠了")
            if i > 0 { XCTAssertTrue(ranked[i - 1].leg.km <= x.leg.km, "沒有照距離排") }
        }
        let first: [String] = nearbyPage(ranked, 0).map { (x: NearbyPick) -> String in x.place.n }
        XCTAssertEqual(first, ["昌德宮與後苑", "清溪川散步", "鍾路蔘雞湯"])
    }

    func test超過走路上限就寫地鐵或公車() throws {
        let t: Trip = try a12Trip()
        var st: Settings = defaultSettings()
        st.walk = .normal
        let normal: [NearbyPick] = nearbyRanked(t, st, 1)
        let museum: NearbyPick = try XCTUnwrap(normal.first { (x: NearbyPick) -> Bool in x.place.n == "國立現代美術館 首爾館" })
        XCTAssertEqual(museum.leg.mode, "地鐵或公車")
        XCTAssertEqual(legText(museum.leg), "地鐵或公車・約 1.2 公里・13 分鐘（估）")
        let stream: NearbyPick = try XCTUnwrap(normal.first { (x: NearbyPick) -> Bool in x.place.n == "清溪川散步" })
        XCTAssertEqual(legText(stream.leg), "走路・約 0.8 公里・10 分鐘（估）")

        st.walk = .lots
        let lots: [NearbyPick] = nearbyRanked(t, st, 1)
        let far: NearbyPick = try XCTUnwrap(lots.first { (x: NearbyPick) -> Bool in x.place.n == "國立現代美術館 首爾館" })
        XCTAssertEqual(far.leg.mode, "走路", "能走的人上限 2 公里")

        st.walk = .less
        let less: [NearbyPick] = nearbyRanked(t, st, 1)
        for x in less where x.leg.km > 0.5 {
            XCTAssertNotEqual(x.leg.mode, "走路", "要少走的人超過 0.5 公里不寫走路：\(x.place.n)")
        }
    }

    func test這天已經有兩個大站就不給大站() throws {
        let t: Trip = try nearbyTrip(
            am: [nearbyStop("景福宮")], pm: [nearbyStop("國立現代美術館 首爾館"), nearbyStop("益善洞韓屋巷")],
            eve: [])
        XCTAssertEqual(bigCount(t, 1), 2)
        let ranked: [NearbyPick] = nearbyRanked(t, defaultSettings(), 1)
        XCTAssertFalse(ranked.contains { (x: NearbyPick) -> Bool in x.place.s == .L })
    }

    func test起點沒有座標_算不出附近() throws {
        var mine: Stop = try nearbyStop("益善洞韓屋巷")
        mine.id = "m-test"
        mine.lat = nil
        mine.lng = nil
        mine.a = nil
        mine.mine = true
        let t: Trip = nearbyTrip(am: [], pm: [mine], eve: [])
        let o: NearbyOrigin = nearbyOrigin(t, defaultSettings(), 1)
        XCTAssertFalse(o.known)
        XCTAssertTrue(nearbyRanked(t, defaultSettings(), 1).isEmpty)
    }

    func test再看三個_看完從頭再來() throws {
        let t: Trip = try a12Trip()
        let ranked: [NearbyPick] = nearbyRanked(t, defaultSettings(), 1)
        XCTAssertTrue(ranked.count > NEARBY_PAGE, "附近要多於三個才測得到")
        let p0: [NearbyPick] = nearbyPage(ranked, 0)
        let p1: [NearbyPick] = nearbyPage(ranked, 1)
        XCTAssertEqual(p0.count, NEARBY_PAGE)
        XCTAssertEqual(p1.first, ranked[NEARBY_PAGE])
        let pages: Int = (ranked.count + NEARBY_PAGE - 1) / NEARBY_PAGE
        XCTAssertEqual(nearbyPage(ranked, pages), p0, "看完了從頭再來")
        XCTAssertTrue(nearbyPage([], 2).isEmpty)
    }

    func test排進起點那一站的時段_過了的時段不排() throws {
        let t: Trip = try a12Trip()
        let o: NearbyOrigin = nearbyOrigin(t, defaultSettings(), 1)
        XCTAssertEqual(nearbyPart(t, 1, o, nil), .pm)
        let evening: TripNow = TripNow(day: 1, part: .eve, clock: "19:00")
        XCTAssertEqual(nearbyPart(t, 1, o, evening), .eve, "下午已經過了")

        let off: Trip = nearbyTrip(am: [], pm: [], eve: [], offAm: true)
        let home: NearbyOrigin = nearbyOrigin(off, defaultSettings(), 1)
        XCTAssertEqual(nearbyPart(off, 1, home, nil), .pm, "上午在路上")
        let late: TripNow = TripNow(day: 2, part: .am, clock: "09:00")
        XCTAssertNil(nearbyPart(off, 1, home, late), "整天都過了")
    }

    func test排進來_排在起點那一站後面() throws {
        var t: Trip = try a12Trip()
        let o: NearbyOrigin = nearbyOrigin(t, defaultSettings(), 1)
        let stream: Place = try nearbyPlace("清溪川散步")
        XCTAssertNil(addNearby(&t, stream, 1, .pm, o.stopId))
        let pm: [String] = dayStops(t, 1).filter { (x: Found) -> Bool in x.s.part == .pm }.map {
            (x: Found) -> String in x.it.n
        }
        XCTAssertEqual(pm, ["益善洞韓屋巷", "清溪川散步", "仁寺洞街"])
        let added: Found = try XCTUnwrap(findItem(t, stream.id))
        XCTAssertEqual(added.it.status, .kept)
        XCTAssertFalse(added.it.why.isEmpty)
        XCTAssertNotNil(addNearby(&t, stream, 1, .pm, nil), "同一個地方不排兩次")
        XCTAssertFalse(nearbyRanked(t, defaultSettings(), 1).contains { (x: NearbyPick) -> Bool in x.place.id == stream.id })

        var off: Trip = nearbyTrip(am: [], pm: [], eve: [], offAm: true)
        let err: String = addNearby(&off, stream, 1, .am, nil) ?? ""
        XCTAssertTrue(err.contains("在路上"), err)
    }
}
