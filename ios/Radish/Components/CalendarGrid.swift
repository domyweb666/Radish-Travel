// 選出發日的月曆。今天以前的日子不能選。
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
    let value: String?
    let onPick: (String) -> Void
    /// 現在翻到哪一年哪一月
    @State private var year: Int
    @State private var month: Int

    init(min: String, value: String?, onPick: @escaping (String) -> Void) {
        self.min = min
        self.value = value
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

    private func dayButton(_ iso: String) -> some View {
        let off: Bool = iso < min
        let on: Bool = iso == value
        let day: Int = calPart(iso, 2)
        let tone: TextTone = off ? .disabled : (on ? .onAccent : .primary)
        return Button {
            onPick(iso)
        } label: {
            DomyText(String(day), .body, tone: tone, lines: 1)
                .frame(width: T.Size.buttonCompact, height: T.Size.buttonCompact)
                .background(on ? C.accent : Color.clear, in: Capsule())
                .frame(maxWidth: .infinity)
                .frame(height: T.Size.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(off)
        .accessibilityLabel("\(month) 月 \(day) 日，星期\(weekday(iso))")
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("cal-\(iso)")
    }
}
