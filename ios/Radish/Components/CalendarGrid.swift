// 選出發日和回來那天的月曆。今天以前的日子不能選。
// 第一下點出發日、第二下點回來那天，兩天之間整段標起來（QC-0013 #104，點了之後怎麼算在 RadishCore 的 DateRange.swift）。
// 對應 mobile/src/components/Calendar.tsx（Foundation 已經有 Calendar，所以改名 CalendarGrid）。
import SwiftUI

private let CAL_WEEK: [String] = ["日", "一", "二", "三", "四", "五", "六"]

/// 'YYYY-MM-DD' 的第幾格數字（0 年、1 月、2 日）。拆不出來當 0
private func calPart(_ iso: String, _ index: Int) -> Int {
    let bits: [String] = iso.components(separatedBy: "-")
    if index < bits.count {
        return Int(bits[index]) ?? 0
    }
    return 0
}

struct CalendarGrid: View {
    let min: String
    /// 出發日
    let value: String?
    /// 回來那天。還沒選、或只選一天的月曆是 nil
    let end: String?
    /// 在等回來那天時，回來那天可以點的範圍。出發日之後、範圍外的日子字變淡（點了會講原因，不會選上）
    let reach: ClosedRange<String>?
    let onPick: (String) -> Void
    /// 現在翻到哪一年哪一月
    @State private var year: Int
    @State private var month: Int

    init(
        min: String, value: String?, end: String? = nil, reach: ClosedRange<String>? = nil,
        onPick: @escaping (String) -> Void
    ) {
        self.min = min
        self.value = value
        self.end = end
        self.reach = reach
        self.onPick = onPick
        let first: String = value ?? min
        self._year = State(initialValue: calPart(first, 0))
        self._month = State(initialValue: calPart(first, 1))
    }

    private var canPrev: Bool {
        let minY: Int = calPart(min, 0)
        let minM: Int = calPart(min, 1)
        return year > minY || (year == minY && month > minM)
    }

    /// 往前或往後翻一個月（n 是 -1 或 1）
    private func step(_ n: Int) {
        var y: Int = year
        var m: Int = month + n
        if m < 1 {
            m = 12
            y -= 1
        } else if m > 12 {
            m = 1
            y += 1
        }
        year = y
        month = m
    }

    var body: some View {
        let cells: [String?] = monthGrid(year, month)
        let rows: Int = cells.count / 7
        VStack(spacing: T.Space.s1) {
            header
            weekRow
            ForEach(0..<rows, id: \.self) { (r: Int) in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { (i: Int) in
                        cell(cells[r * 7 + i])
                    }
                }
            }
        }
        .padding(T.Space.s3)
        .background(C.surface, in: RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 0) {
            arrow("上個月", "‹", "cal-prev", canPrev) { step(-1) }
            Spacer(minLength: 0)
            DomyText("\(year) 年 \(month) 月", .headline)
            Spacer(minLength: 0)
            arrow("下個月", "›", "cal-next", true) { step(1) }
        }
    }

    private func arrow(
        _ label: String, _ text: String, _ identifier: String, _ enabled: Bool,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            DomyText(text, .title3, tone: enabled ? .strong : .disabled)
                .frame(width: T.Size.touch, height: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private var weekRow: some View {
        HStack(spacing: 0) {
            ForEach(CAL_WEEK, id: \.self) { (w: String) in
                DomyText(w, .caption, tone: .secondary, align: .center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func cell(_ iso: String?) -> some View {
        if let iso {
            dayButton(iso)
        } else {
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: T.Size.touch)
        }
    }

    /// 這天在不在出發到回來之間（含兩端）
    private func inRange(_ iso: String) -> Bool {
        guard let s = value, let e = end else { return false }
        return iso >= s && iso <= e
    }

    /// 在等回來那天，而這天在出發日之後、卻不能當回來那天
    private func outOfReach(_ iso: String) -> Bool {
        guard let r = reach, let s = value else { return false }
        return iso > s && !r.contains(iso)
    }

    /// 中間那條淡底：出發日只畫右半、回來那天只畫左半，中間的整格畫滿，連成一條
    private func band(_ iso: String) -> some View {
        let on: Bool = inRange(iso) && value != end
        let left: Bool = on && iso != value
        let right: Bool = on && iso != end
        return HStack(spacing: 0) {
            (left ? C.soft : Color.clear)
            (right ? C.soft : Color.clear)
        }
        .frame(height: T.Size.buttonCompact)
        .accessibilityHidden(true)
    }

    private func dayTone(_ iso: String, _ off: Bool, _ edge: Bool) -> TextTone {
        if off || outOfReach(iso) { return .disabled }
        return edge ? .onAccent : .primary
    }

    /// 念給 VoiceOver 聽的：哪天，加上是出發、回來還是在這趟裡
    private func dayLabel(_ iso: String, _ day: Int) -> String {
        let head: String = "\(month) 月 \(day) 日，星期\(weekday(iso))"
        if iso == value { return head + "，出發" }
        if iso == end { return head + "，回來" }
        if inRange(iso) { return head + "，在這趟裡" }
        return head
    }

    private func dayButton(_ iso: String) -> some View {
        let off: Bool = iso < min
        let edge: Bool = iso == value || iso == end
        let day: Int = calPart(iso, 2)
        return Button {
            onPick(iso)
        } label: {
            DomyText(String(day), .body, tone: dayTone(iso, off, edge), lines: 1)
                .frame(width: T.Size.buttonCompact, height: T.Size.buttonCompact)
                .background(edge ? C.accent : Color.clear, in: Capsule())
                .frame(maxWidth: .infinity)
                .background { band(iso) }
                .frame(height: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .accessibilityLabel(dayLabel(iso, day))
        .accessibilityAddTraits(edge ? [.isSelected] : [])
        .accessibilityIdentifier("cal-\(iso)")
    }
}
