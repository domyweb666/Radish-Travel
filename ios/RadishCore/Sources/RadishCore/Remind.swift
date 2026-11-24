// 「要先訂的還沒訂」的提醒：哪一天提醒、提醒什麼。這裡只算，真的排通知在 app 那邊。
// 照 mobile/src/domain/remind.ts 搬。
import Foundation

private let AHEAD: Int = 7  // 出發前幾天提醒

/// 要先訂、還沒在「行前」打勾、也還沒去的站
func unbookedOf(_ trip: Trip, _ checks: [String: Bool]) -> [Stop] {
    var out: [Stop] = []
    for x in allItems(trip) {
        let it: Stop = x.it
        if it.b == true && it.status == .kept && checks["b_" + it.id] != true {
            out.append(it)
        }
    }
    return out
}

/// 哪一天提醒：出發前七天；已經不到七天就明天；明天就出發或已經出發就不提醒
func remindOn(_ start: String, _ today: String) -> String? {
    let early: String = addDays(start, -AHEAD)
    let on: String = early > today ? early : addDays(today, 1)
    return on < start ? on : nil
}

struct Reminder: Hashable, Sendable {
    var on: String
    var title: String
    var body: String
}

/// 這一天早上九點，給系統排通知用。寫明是西元：不寫的話，系統會拿手機設的行事曆（佛曆、民國曆）去解讀年份。
/// 日期拆不出來就是 nil
func reminderTime(_ on: String) -> DateComponents? {
    let parts: [Int] = on.components(separatedBy: "-").compactMap { (x: String) -> Int? in Int(x) }
    guard parts.count == 3 else { return nil }
    var when: DateComponents = DateComponents()
    when.calendar = Calendar(identifier: .gregorian)
    when.year = parts[0]
    when.month = parts[1]
    when.day = parts[2]
    when.hour = 9
    return when
}

/// 現在這趟和其他排好的，每一趟最多一則。沒有還沒訂的就沒有提醒
func remindersOf(_ s: AppState, _ today: String) -> [Reminder] {
    var all: [(trip: Trip, checks: [String: Bool])] = []
    if let trip = s.trip {
        all.append((trip: trip, checks: s.checks))
    }
    for x in s.shelf {
        all.append((trip: x.trip, checks: x.checks))
    }
    var out: [Reminder] = []
    for pair in all {
        let trip: Trip = pair.trip
        let left: [Stop] = unbookedOf(trip, pair.checks)
        let onDay: String? = remindOn(trip.start, today)
        guard !left.isEmpty, let on = onDay else { continue }
        let names: [String] = left.map { (x: Stop) -> String in x.n }
        out.append(
            Reminder(
                on: on,
                title: "\(tripTitle(trip))・\(fmtDay(trip.start))出發",
                body: "有 \(left.count) 站要先訂，還沒打勾：\(names.joined(separator: "、"))。"
            ))
    }
    return out
}
