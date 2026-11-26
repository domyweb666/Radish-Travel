// 住宿偏好（QC-0013 #105）：多一種五星級飯店、舊檔讀得回來、估花費照它算、送給 AI 的習慣裡有它。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

private func stayDraft(tweaks: [Tweak]? = nil) -> TripDraft {
    return TripDraft(
        tweaks: tweaks, city: nil, base: nil, stayName: nil, name: nil, cover: nil,
        start: "2026-12-04", days: 5, arrive: .am, leave: .eve, people: 1
    )
}

final class StayPrefTests: XCTestCase {
    func test每一種住宿偏好都有資料_越往後越貴() throws {
        // 少了哪一種，app 一讀到 STAY[need:] 就當掉。重轉 seoul.json 弄丟 lux 時這裡會擋
        XCTAssertEqual(StayKind.allCases, [.cheap, .mid, .nice, .lux])
        var last: Double = 0
        for k in StayKind.allCases {
            let text: StayText = try XCTUnwrap(STAY[k], "\(k) 沒有資料")
            XCTAssertGreaterThan(text.perNight, last, "\(k) 一晚的粗估要比前一種貴")
            last = text.perNight
        }
        XCTAssertEqual(STAY[need: .cheap].label, "便宜就好（青旅、民宿）")
        XCTAssertEqual(STAY[need: .mid].label, "一般（商務旅館）")
        XCTAssertEqual(STAY[need: .nice].label, "舒服一點（四星）")
        XCTAssertEqual(STAY[need: .lux].label, "五星級飯店")
    }

    func test舊檔的住宿照舊讀得回來_新的五星級也讀得回來() throws {
        let pairs: [(String, StayKind)] = [("cheap", .cheap), ("mid", .mid), ("nice", .nice), ("lux", .lux)]
        for (raw, kind) in pairs {
            let json: Data = try XCTUnwrap("{\"stay\":\"\(raw)\",\"budget\":2500}".data(using: .utf8))
            let st: Settings = try JSONDecoder().decode(Settings.self, from: json)
            XCTAssertEqual(st.stay, kind)
            XCTAssertEqual(st.budget, 2500)
        }
        // 沒有這一欄的舊檔用預設
        let bare: Data = try XCTUnwrap("{}".data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: bare).stay, defaultSettings().stay)
    }

    func test估花費照住宿偏好算_想省一點就照便宜的() throws {
        var st: Settings = defaultSettings()
        st.stay = .lux
        let t: Trip = generate(stayDraft(), st)
        let row: CostRow = try XCTUnwrap(cost(t, st).rows.first { (r: CostRow) -> Bool in r.name == "住宿" })
        XCTAssertEqual(row.amount, 4 * STAY[need: .lux].perNight)
        XCTAssertEqual(tripSettings(st, [.save]).stay, StayKind.cheap)
    }

    func test送給AI的習慣裡有住宿偏好_也講問住哪時照它推薦() throws {
        var st: Settings = defaultSettings()
        st.stay = .nice
        st.base = .C
        let summary: String = settingsSummary(st)
        XCTAssertTrue(summary.contains("住宿偏好：舒服一點（四星）"), summary)
        XCTAssertTrue(summary.contains("住\(HOTEL[need: .C].n)一帶"), summary)
        let t: Trip = generate(stayDraft(), st)
        let prompt: String = aiPrompt("住哪裡比較好", t, st, [])
        XCTAssertTrue(prompt.contains("住宿偏好：舒服一點（四星）"))
        XCTAssertTrue(prompt.contains("推薦旅館"))
        // 這趟想省一點：送出去的也跟著變便宜的
        let saving: Trip = generate(stayDraft(tweaks: [.save]), st)
        XCTAssertTrue(aiPrompt("住哪裡比較好", saving, st, []).contains("住宿偏好：便宜就好（青旅、民宿）"))
    }
}
