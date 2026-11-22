// 從這趟推進的三頁：檢查這趟、須知、花費。原本是「行前」分頁的四段（.uiux/02-流程-暫定.md 5-4）。
// 裡面的內容沿用 PrepBefore、PrepThere、PrepBack、PrepCost；這個檔只放外框和「按天」那一段。
// 線框：.uiux/03-線框/線框/Check.dc.html、Notes.dc.html、A18-Cost.dc.html
import SwiftUI

/// 日期那一行：12/16（三）– 12/20（日）
private func tripRange(_ trip: Trip) -> String {
    return "\(fmtDay(trip.start)) – \(fmtDay(addDays(trip.start, trip.days - 1)))"
}

/// 沒有這趟時的空白頁（從開一趟那頁進來、或這趟剛收起來）
private struct NoTrip: View {
    @Environment(Nav.self) private var nav
    let message: String

    var body: some View {
        DomyEmptyState(
            icon: IconPaths.tabTrip,
            title: "還沒有這趟",
            message: message,
            actionTitle: "去排一趟",
            action: { nav.show(.trip) }
        )
    }
}

/* ---------- 檢查這趟 ---------- */

/// 檢查這趟：要先訂的、提醒、要辦的事、行李、不能帶進韓國的（S11）
struct CheckScreen: View {
    @Environment(AppStore.self) private var store

    private func subtitle(_ trip: Trip) -> String {
        let range: String = tripRange(trip)
        switch store.phase {
        case .plan(let daysToGo)?:
            return "還有 \(daysToGo) 天出發・\(range)"
        case .trip(let day)?:
            return "旅途中，今天第 \(day) 天・\(range)"
        case .done?:
            return "已經回來了・\(range)"
        case nil:
            return range
        }
    }

    var body: some View {
        Screen("檢查這趟") {
            if let trip = store.s.trip {
                DomyText(subtitle(trip), .subheadline, tone: .secondary)
                    .padding(.top, -T.Space.s4)
                PrepBefore()
            } else {
                NoTrip(message: "排好一趟之後，這裡會列出要先訂的、要辦的事和行李。")
            }
        }
    }
}

/* ---------- 須知 ---------- */

enum NotesPart: Hashable {
    case there, day, back
}

/// 須知：在當地、按天（一次看一天）、回程（S13）。沒有這趟時只有在當地、回程
struct NotesScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(Nav.self) private var nav
    /// nil 是還沒點過：照這趟走到哪決定先開哪一段
    @State private var picked: NotesPart?
    /// 按天那一段在看第幾天。nil 是旅途中的今天，不在旅途中是第 1 天
    @State private var noteDay: Int?

    private var today: Int? {
        if case .trip(let d)? = store.phase { return d }
        return nil
    }

    /// 還沒出發先看在當地；旅途中看今天那幾站；最後一天和回來之後看回程
    private var auto: NotesPart {
        guard store.s.trip != nil, let phase = store.phase else { return .there }
        switch phase {
        case .plan:
            return .there
        case .trip(let d):
            return d >= (store.s.trip?.days ?? 0) ? .back : .day
        case .done:
            return .back
        }
    }

    private var part: NotesPart {
        let p: NotesPart = picked ?? auto
        if p == .day && store.s.trip == nil { return .there }
        return p
    }

    private var options: [(NotesPart, String)] {
        if store.s.trip == nil {
            return [(NotesPart.there, "在當地"), (NotesPart.back, "回程")]
        }
        return [(NotesPart.there, "在當地"), (NotesPart.day, "按天"), (NotesPart.back, "回程")]
    }

    var body: some View {
        Screen("須知") {
            Segmented(value: part, options: options) { (next: NotesPart) in
                picked = next
            }
            switch part {
            case .there:
                PrepThere()
            case .day:
                if let trip = store.s.trip {
                    byDay(trip)
                }
            case .back:
                PrepBack()
            }
        }
    }

    private func shownDay(_ trip: Trip) -> Int {
        return max(1, min(noteDay ?? today ?? 1, trip.days))
    }

    @ViewBuilder
    private func byDay(_ trip: Trip) -> some View {
        let shown: Int = shownDay(trip)
        let stops: [Found] = dayStops(trip, shown)
        TripDayTabs(trip: trip, value: shown, today: today) { (d: Int) in
            noteDay = d
        }
        if stops.isEmpty {
            DomyEmptyState(title: "這天沒有排站", message: "在路上或留白的日子，沒有要注意的站。")
        } else {
            DomySection(footer: "這幾站的須知都還沒核對過，去之前再查一下。") {
                ForEach(stops, id: \.it.id) { (x: Found) in
                    NoteRow(meta: PART[need: x.s.part], name: x.it.n, tip: x.it.tip) {
                        nav.push(.stop(id: x.it.id))
                    }
                    .accessibilityIdentifier("note-row-\(x.it.id)")
                }
            }
        }
    }
}

/// 按天的一列：時段、站名、那一站的須知。點了打開那一站
private struct NoteRow: View {
    let meta: String
    let name: String
    let tip: String?
    let action: () -> Void

    private var tipText: String {
        if let tip, !tip.isEmpty { return tip }
        return "這一站還沒有須知"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: T.Space.s3) {
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    DomyText(meta, .footnote, tone: .secondary)
                    DomyText(name, .headline)
                    DomyText(tipText, .subheadline, tone: .secondary)
                }
                .fillLeading()
                Chevron()
            }
            .padding(.vertical, T.Space.s3)
            .frame(minHeight: T.Size.row)
            .padding(.horizontal, T.Space.s4)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .padding(.horizontal, -T.Space.s4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(meta)，\(name)，\(tipText)")
        .accessibilityAddTraits(.isButton)
    }
}

/* ---------- 花費 ---------- */

/// 花費：每人大概花多少（估）、換算、記一筆（S14）。從更多進來，旅途中也從下一站卡下面進來
struct CostScreen: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        Screen("花費") {
            if store.s.trip != nil {
                PrepCost()
            } else {
                NoTrip(message: "排好一趟之後，這裡會有每人大概要花多少。")
            }
        }
    }
}
