// 用講的改行程時，AI 要知道「現在」：還沒出發、旅途中第幾天幾點、還是已經回來了。
// 旅途中已經過去的時段、已經拔起來的站，AI 和本機指令都不准動。
// 這個檔是 SwiftUI 版才有的，mobile/ 沒有對應的 TS。
import Foundation

/// 按下送出那一刻：這趟在哪個階段、手機上幾點幾分
struct ChatClock: Equatable, Sendable {
    var phase: Phase
    var hour: Int
    var minute: Int
}

/// 旅途中的現在。part 是現在所在的時段，它之前的時段算已經過了
struct TripNow: Equatable, Sendable {
    var day: Int
    var part: Part
    var clock: String
}

/// 幾點算哪個時段：中午 12 點前上午，下午 6 點前下午，之後晚上
func partAt(_ hour: Int) -> Part {
    if hour < 12 { return Part.am }
    if hour < 18 { return Part.pm }
    return Part.eve
}

/// 用手機當地時間組一個 ChatClock
func chatClock(_ phase: Phase, _ date: Date = Date()) -> ChatClock {
    let c: DateComponents = Calendar.current.dateComponents([.hour, .minute], from: date)
    return ChatClock(phase: phase, hour: c.hour ?? 0, minute: c.minute ?? 0)
}

private func nowPad(_ n: Int) -> String {
    return n < 10 ? "0\(n)" : "\(n)"
}

/// 不在旅途中就是 nil
func tripNow(_ c: ChatClock?) -> TripNow? {
    guard let c = c else { return nil }
    guard case .trip(let day) = c.phase else { return nil }
    return TripNow(day: day, part: partAt(c.hour), clock: "\(nowPad(c.hour)):\(nowPad(c.minute))")
}

private func partIndex(_ p: Part) -> Int {
    return PARTS.firstIndex(of: p) ?? 0
}

/// 這個時段是不是已經過了。現在所在的時段不算過（還能換、還能留白）
func slotPast(_ now: TripNow?, _ day: Int, _ part: Part) -> Bool {
    guard let n = now else { return false }
    if day < n.day { return true }
    if day > n.day { return false }
    return partIndex(part) < partIndex(n.part)
}

/// 這個時段還能不能排東西進去（移進去、加進去）。能回 nil，不能回原因。用講的和移站共用這一句
func slotPastWhy(_ now: TripNow?, _ day: Int, _ part: Part) -> String? {
    if slotPast(now, day, part) { return "第 \(day) 天\(PART[part] ?? "")已經過了，不能再排" }
    return nil
}

/// 這一天有沒有不能整天搬的東西：過去的時段，或拔起來的站
func dayFrozen(_ t: Trip, _ now: TripNow?, _ day: Int) -> Bool {
    for p in PARTS where slotPast(now, day, p) { return true }
    return dayStops(t, day).contains { (x: Found) -> Bool in x.it.status == .pulled }
}

/// 第 3 天的日期，例如 12/6（六）
func tripDayLabel(_ t: Trip, _ day: Int) -> String {
    return fmtDay(addDays(t.start, day - 1))
}

/// 提示詞裡講「現在」的那一段
func nowLine(_ t: Trip, _ c: ChatClock?) -> String {
    guard let c = c else { return "" }
    switch c.phase {
    case .plan(let daysToGo):
        return "現在還沒出發，離出發還有 \(daysToGo) 天。"
    case .done:
        return "這趟已經回來了。"
    case .trip(let day):
        let n: TripNow? = tripNow(c)
        let clock: String = n?.clock ?? ""
        let part: String = PART[need: partAt(c.hour)]
        return "現在是旅途中第 \(day) 天 \(tripDayLabel(t, day)) \(clock)，\(part)。"
    }
}
