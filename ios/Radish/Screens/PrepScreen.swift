// 原本「行前」分頁的四段共用的小元件。四段現在拆到推進頁（TripPages.swift）：
// 出發前 → 檢查這趟（PrepBefore）、在當地和回程 → 須知（PrepThere、PrepBack）、花費 → 花費（PrepCost）。
// 每一條只留一行短的核對狀態；完整的來源收在「看每一條的來源」。
// 對應 mobile/src/screens/PrepScreen.tsx。
import SwiftUI

/// 列上只放短的：二手資料・11/14，或是未核對
func prepFactShort(_ f: Fact) -> String {
    if f.checked.isEmpty { return "未核對" }
    let parts: [String] = f.checked.components(separatedBy: "-")
    guard parts.count >= 3, let m = Int(parts[1]), let d = Int(parts[2]) else {
        return "\(statusWord(f.status))・\(f.checked)"
    }
    return "\(statusWord(f.status))・\(m)/\(d)"
}

func prepFactFull(_ f: Fact) -> String {
    if f.checked.isEmpty { return "還沒核對過，沒有來源" }
    return "\(statusWord(f.status)) \(f.checked)・來源：\(f.source)"
}

/// 檢查表、地雷的每一條在 TS 都是 Fact 多幾欄；Swift 是不同的型別，要一起列來源時先轉成 Fact
/// 檢查表的字跟著出發日期走，核對狀態和來源跟著換。start 是這趟到的那天，沒有這趟就用原本的
func prepFact(_ r: CheckItem, _ start: String? = nil) -> Fact {
    let plain: Fact = Fact(text: r.text, status: r.status, checked: r.checked, source: r.source)
    return datedFact(r.id, plain, start)
}

func prepFact(_ r: TabooFact) -> Fact {
    return Fact(text: r.text, status: r.status, checked: r.checked, source: r.source)
}

/// TS 的 TextRow 碰到空字串的 note 不會畫；Swift 的 TextRow 只看是不是 nil，所以空的先轉成 nil
func prepNote(_ text: String?) -> String? {
    guard let text, !text.isEmpty else { return nil }
    return text
}

private struct PrepSources: View {
    let title: String
    let facts: [Fact]
    let onClose: () -> Void

    var body: some View {
        SheetScaffold(title, onClose: onClose) {
            DomyText(
                "「看過官方頁」是直接讀過官方頁。「二手資料」是從旅遊媒體交叉對過，沒有直接讀官方頁。「來源較舊」是找到的資料比較舊，可能已經變了。「未核對」是還沒查。入境規定出發前請回官方頁再看一次。",
                .subheadline, tone: .secondary)
            DomySection {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, f in
                    TextRow(f.text, note: prepNote(prepFactFull(f)))
                }
            }
        }
    }
}

/// 每一段最下面那顆「看每一條的來源」
struct PrepSourcesButton: View {
    let title: String
    let facts: [Fact]
    @State private var open: Bool = false

    init(title: String, facts: [Fact]) {
        self.title = title
        self.facts = facts
    }

    var body: some View {
        DomyButton("看每一條的來源", variant: .plain, fullWidth: true) {
            open = true
        }
        .accessibilityIdentifier("prep-sources")
        .sheet(isPresented: $open) {
            PrepSources(title: title, facts: facts) {
                open = false
            }
            .tint(C.accent)
        }
    }
}

struct PrepFactList: View {
    let title: String
    let facts: [Fact]
    var footer: String?

    init(title: String, facts: [Fact], footer: String? = nil) {
        self.title = title
        self.facts = facts
        self.footer = footer
    }

    var body: some View {
        DomySection(title, footer: footer) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, r in
                TextRow(r.text, note: prepNote(prepFactShort(r)))
            }
        }
    }
}

struct PrepPickList: View {
    let title: String
    let items: [Tip]
    var footer: String?

    init(title: String, items: [Tip], footer: String? = nil) {
        self.title = title
        self.items = items
        self.footer = footer
    }

    private func name(_ p: Tip) -> String {
        if let kr = p.kr, !kr.isEmpty {
            return "\(p.n)　\(kr)"
        }
        return p.n
    }

    var body: some View {
        DomySection(title, footer: footer) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, p in
                TextRow(name(p), note: prepNote(p.note))
            }
        }
    }
}
