// 手機的行事曆設成佛曆、日本曆、民國曆時，日期還是要算成西元。
// SwiftUI 版才有，mobile/tests 沒有對應的。
import XCTest

@testable import RadishCore

final class DateCalendarTests: XCTestCase {
    /// 2026-11-24 12:00 UTC
    private let noon: Date = Date(timeIntervalSince1970: 1_795_521_600)

    private func device(_ id: Calendar.Identifier, _ zone: String) throws -> Calendar {
        var cal: Calendar = Calendar(identifier: id)
        cal.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
        return cal
    }

    func test手機設佛曆_日本曆_民國曆_今天還是西元() throws {
        let ids: [Calendar.Identifier] = [.gregorian, .buddhist, .japanese, .republicOfChina]
        for id in ids {
            let cal: Calendar = try device(id, "Asia/Taipei")
            XCTAssertEqual(todayISO(noon, device: cal), "2026-11-24", "\(id)")
        }
    }

    func test今天照手機當地的時區算() throws {
        // 16:30 UTC：台北已經隔天 00:30，檀香山還是當天早上 06:30
        let late: Date = noon.addingTimeInterval(16_200)
        let taipei: Calendar = try device(.buddhist, "Asia/Taipei")
        let honolulu: Calendar = try device(.buddhist, "Pacific/Honolulu")
        XCTAssertEqual(todayISO(late, device: taipei), "2026-11-25")
        XCTAssertEqual(todayISO(late, device: honolulu), "2026-11-24")
    }

    func test通知的時間寫明是西元早上九點() throws {
        let when: DateComponents = try XCTUnwrap(reminderTime("2026-11-24"))
        XCTAssertEqual(when.calendar?.identifier, Calendar.Identifier.gregorian)
        XCTAssertEqual(when.year, 2026)
        XCTAssertEqual(when.month, 11)
        XCTAssertEqual(when.day, 24)
        XCTAssertEqual(when.hour, 9)
        XCTAssertNil(reminderTime("2026-11"))
    }
}
