// 開一趟、行程設定的月曆選區間（QC-0013 #104）：第一下點出發日，第二下點回來那天。
// 資料還是存出發日＋天數（TripDraft 的 start、days），這裡只管點了一下之後這兩個值變成什麼。
// SwiftUI 版才有，mobile/ 是「去幾天」那排按鈕，沒有對應的。
import Foundation

/// 一趟最少、最多幾天。原本「去幾天」那排是 3 天到 14 天
let TRIP_DAYS_MIN: Int = 3
let TRIP_DAYS_MAX: Int = 14

/// 月曆現在在等哪一下
enum RangeStep: Equatable, Sendable {
    /// 下一下是出發日（還沒選，或兩端都選好了，再點就重選）
    case start
    /// 出發日選了，下一下是回來那天
    case end
}

/// 月曆點了一下之後的出發日和天數。note 是這一下沒照點的改時要講的那句，照點的改了就是 nil
struct RangePick: Equatable, Sendable {
    var start: String?
    var days: Int?
    var note: String?
}

func rangeStep(_ start: String?, _ days: Int?) -> RangeStep {
    guard let s = start, !s.isEmpty else { return .start }
    return (days ?? 0) == 0 ? .end : .start
}

/// 回來那天：出發日加天數減一。還沒選好是 nil
func rangeEnd(_ start: String?, _ days: Int?) -> String? {
    guard let s = start, !s.isEmpty, let n = days, n > 0 else { return nil }
    return addDays(s, n - 1)
}

/// 出發日選了、在等回來那天時，回來那天最早和最晚可以點哪天
func rangeReach(_ start: String) -> ClosedRange<String> {
    return addDays(start, TRIP_DAYS_MIN - 1)...addDays(start, TRIP_DAYS_MAX - 1)
}

/// 點了 tapped 這天：
/// - 還沒選出發日，或兩端都選好了：這天當出發日，回來那天清掉重選
/// - 在等回來那天：比出發日早的當新的出發日；太近、太遠的不收，講原因；其他的就是回來那天
func pickRange(_ start: String?, _ days: Int?, tapped: String) -> RangePick {
    guard rangeStep(start, days) == .end, let s = start else {
        return RangePick(start: tapped, days: nil, note: nil)
    }
    if tapped < s {
        return RangePick(start: tapped, days: nil, note: nil)
    }
    let span: Int = diffDays(s, tapped) + 1
    if span < TRIP_DAYS_MIN {
        let first: String = fmtDay(addDays(s, TRIP_DAYS_MIN - 1))
        return RangePick(start: s, days: nil, note: "最少去 \(TRIP_DAYS_MIN) 天，回來那天最早是 \(first)。")
    }
    if span > TRIP_DAYS_MAX {
        let last: String = fmtDay(addDays(s, TRIP_DAYS_MAX - 1))
        return RangePick(start: s, days: nil, note: "最多去 \(TRIP_DAYS_MAX) 天，回來那天最晚是 \(last)。")
    }
    return RangePick(start: s, days: span, note: nil)
}

/// 月曆上面那一行：「12/1（二）出發・12/8（二）回來・共 8 天」
func rangeLine(_ start: String?, _ days: Int?) -> String {
    guard let s = start, !s.isEmpty else { return "點出發那天" }
    guard let end = rangeEnd(s, days), let n = days else {
        return "\(fmtDay(s))出發・再點回來那天"
    }
    return "\(fmtDay(s))出發・\(fmtDay(end))回來・共 \(n) 天"
}
