// 「要先訂的還沒訂」的提醒：哪一天提醒、提醒什麼。這裡只算，真的排通知在 app 那邊。
// 原本照 mobile/src/domain/remind.ts，一趟一則。現在知道什麼時候開賣的一站一則，其他的併成一則。
import Foundation

private let AHEAD: Int = 7  // 出發前幾天提醒
private let LEAD_MINUTES: Int = 15  // 開賣前幾分鐘提醒
private let REMIND_HOUR: Int = 9  // 沒有幾點的，早上九點提醒
private let REMIND_MAX: Int = 40  // 最多排幾則。系統的上限是 64

/// 要先訂、還沒在「行前」打勾、也還沒去的站
func unbookedOf(_ trip: Trip, _ checks: [String: Bool]) -> [Stop] {
    var out: [Stop] = []
    for x in allItems(trip) {
        let it: Stop = x.it
        if needsBook(it) && it.status == .kept && checks["b_" + it.id] != true {
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
    /// 同名同一天的也分得開：第幾趟、哪一種、哪一站
    var id: String
    /// 哪一天。有 at 的是台灣的日期
    var on: String
    /// 絕對的那一刻，1970 起算第幾秒。nil 是那天手機當地的早上九點
    var at: Double?
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
    when.hour = REMIND_HOUR
    return when
}

/// 一則提醒的時間，給系統排通知用。開賣的那種寫明韓國時區，手機在哪裡都是同一刻
func reminderTime(_ r: Reminder) -> DateComponents? {
    guard let at = r.at else { return reminderTime(r.on) }
    let korea: (on: String, minutes: Int) = koreaLocal(at)
    guard let day: DateComponents = reminderTime(korea.on) else { return nil }
    guard let zone = TimeZone(identifier: "Asia/Seoul") else { return nil }
    var cal: Calendar = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    var when: DateComponents = day
    when.calendar = cal
    when.timeZone = zone
    when.hour = korea.minutes / 60
    when.minute = korea.minutes % 60
    return when
}

/// 排先後、算過了沒用的那一刻。早上九點那種是手機當地的九點
func remindSeconds(_ r: Reminder, _ zone: TimeZone = TimeZone.current) -> Double {
    return r.at ?? zoneSeconds(r.on, REMIND_HOUR * 60, zone)
}

/// 給人看的時間：「12/2（三）早上 8:45（台灣時間）」「12/2（三）早上 9 點」
func remindWhen(_ r: Reminder) -> String {
    guard let at = r.at else { return "\(fmtDay(r.on))早上 9 點" }
    let tw: (on: String, minutes: Int) = taiwanLocal(at)
    let half: Int = tw.minutes >= 13 * 60 ? tw.minutes - 12 * 60 : tw.minutes
    return "\(fmtDay(tw.on))\(remindPart(tw.minutes)) \(bookClock(half))（台灣時間）"
}

private func remindPart(_ minutes: Int) -> String {
    let h: Int = minutes / 60
    if h < 5 { return "凌晨" }
    if h < 12 { return "早上" }
    if h < 13 { return "中午" }
    return h < 18 ? "下午" : "晚上"
}

/// 現在這趟和其他排好的，要排的提醒，照時間先後，最多 40 則。
/// now 是現在時刻，沒給就當成今天剛開始。fact 是查核對資料的那一個，zone 是手機的時區
func remindersOf(
    _ s: AppState, _ today: String, now: Date? = nil, fact: (String) -> PlaceFact? = factOf,
    zone: TimeZone = TimeZone.current
) -> [Reminder] {
    var all: [(trip: Trip, checks: [String: Bool])] = []
    if let trip = s.trip {
        all.append((trip: trip, checks: s.checks))
    }
    for x in s.shelf {
        all.append((trip: x.trip, checks: x.checks))
    }
    var list: [Reminder] = []
    var n: Int = 0
    for pair in all {
        list += tripReminders(pair.trip, pair.checks, "\(n)", today, now, fact, zone)
        n += 1
    }
    return firstReminders(list, zone)
}

/// 照時間先後留前面的。同一刻的照原本的順序
private func firstReminders(_ list: [Reminder], _ zone: TimeZone) -> [Reminder] {
    let order: [Int] = Array(list.indices).sorted { (a: Int, b: Int) -> Bool in
        let x: Double = remindSeconds(list[a], zone)
        let y: Double = remindSeconds(list[b], zone)
        return x == y ? a < b : x < y
    }
    let kept: [Reminder] = order.map { (i: Int) -> Reminder in list[i] }
    return Array(kept.prefix(REMIND_MAX))
}

/// 一趟的提醒。知道什麼時候開賣的一站一則，其他還沒訂的併成一則；最晚要決定的那天再一則
private func tripReminders(
    _ trip: Trip, _ checks: [String: Bool], _ key: String, _ today: String, _ now: Date?,
    _ fact: (String) -> PlaceFact?, _ zone: TimeZone
) -> [Reminder] {
    // 整趟走完的不排。旅途中只剩開賣和最後決定日這兩種（合併那則 remindOn 出發後就沒有）
    if today >= addDays(trip.start, trip.days) { return [] }
    let clock: Double = bookNow(today, now)
    var out: [Reminder] = []
    var left: [String] = []
    let rows: [BookRow] = bookPlan(trip, checks, today, now: now, fact: fact)
    for r in rows {
        if r.checked || r.stop.status != StopStatus.kept { continue }
        var openDay: String? = nil
        if let open = openReminder(r, key), remindSeconds(open, zone) > clock {
            out.append(open)
            openDay = open.on
        } else {
            left.append(r.stop.n)
        }
        // 同一天已經有開賣那則，就只留那則
        if let decide = decideReminder(r, key), remindSeconds(decide, zone) > clock, decide.on != openDay {
            out.append(decide)
        }
    }
    if !left.isEmpty, let on = remindOn(trip.start, today) {
        out.append(
            Reminder(
                id: "\(key)-all",
                on: on,
                at: nil,
                title: "\(tripTitle(trip))・\(fmtDay(trip.start))出發",
                body: "有 \(left.count) 站要先訂，還沒打勾：\(left.joined(separator: "、"))。"
            ))
    }
    return out
}

/// 開賣前 15 分鐘；只知道哪天開賣的，那天早上九點。不知道或已經開賣就是 nil。吃的講開放訂位
private func openReminder(_ r: BookRow, _ key: String) -> Reminder? {
    guard r.stage == BookStage.notYet, let on = r.openOn else { return nil }
    let open: String = bookWords(r.stop.c).open
    let id: String = "\(key)-open-\(r.id)"
    let body: String = "\(bookWhen(r))要去。" + bookHowText(r)
    if let seconds = r.openSeconds, let at = r.openAt {
        let early: Double = seconds - Double(LEAD_MINUTES * 60)
        return Reminder(
            id: id,
            on: taiwanLocal(early).on,
            at: early,
            title: "\(r.stop.n) \(at)（台灣時間）\(open)",
            body: body
        )
    }
    return Reminder(
        id: id,
        on: on,
        at: nil,
        title: "\(r.stop.n)今天\(open)",
        body: "幾點\(open)還不知道。" + body
    )
}

/// 最晚要決定的那天早上九點。期限照資料寫，不保證
private func decideReminder(_ r: BookRow, _ key: String) -> Reminder? {
    guard let on = r.decideOn else { return nil }
    let from: String = r.status == FactStatus.official ? "官方頁寫" : "查到的資料寫"
    let when: String = "\(bookWhen(r))要去，還沒打勾。"
    return Reminder(
        id: "\(key)-decide-\(r.id)",
        on: on,
        at: nil,
        title: "\(r.stop.n)今天要決定",
        body: "\(from)今天是免費取消的最後一天，以訂的那邊為準。" + when
    )
}
