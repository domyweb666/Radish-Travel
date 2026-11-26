// 代購（推進頁）：朋友家人託這趟幫買的東西。照誰託的分組，點一下勾買到；可以加、改、刪，都能復原。
// 跟檢查這趟、須知、花費同一層，從這趟標題下面的「代購」進來；總覽頁做好之後收進總覽。
// 規則在 RadishCore 的 Errands.swift。不算進花費，畫面上也不出現價錢加總。mobile/ 沒有對應的檔。
import SwiftUI

/// 輸入框的字數上限：超過就切掉。回 nil 是沒超過
private func cutOver(_ text: String, _ limit: Int) -> String? {
    return text.count > limit ? String(text.prefix(limit)) : nil
}

/// 打到一半的一列。加一樣、改一樣共用
private struct ErrandDraft: Equatable {
    var who: String = ""
    var what: String = ""
    var qty: Int = 1
    var note: String = ""
}

/// 買什麼還沒寫：按鈕先停用
private func draftBlank(_ x: ErrandDraft) -> Bool {
    return x.what.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

struct ErrandsScreen: View {
    @Environment(AppStore.self) private var store
    /// 加一樣那張卡正在打的字
    @State private var draft: ErrandDraft = ErrandDraft()
    /// 正在改的那一列。nil 是沒在改
    @State private var editing: String? = nil
    /// 正在改的那一列打到一半的字
    @State private var edit: ErrandDraft = ErrandDraft()

    init() {}

    var body: some View {
        Screen("代購") {
            if let trip = store.s.trip {
                content(trip)
            } else {
                NoTrip(message: "排好一趟之後，可以在這裡記別人託你買的東西。")
            }
        }
    }

    /// 最上面一行還差幾樣，再來每個人一組，最後是加一樣
    @ViewBuilder
    private func content(_ trip: Trip) -> some View {
        let list: [Errand] = trip.errands ?? []
        let names: [String] = errandNames(list)
        if let line = errandsLine(list) {
            DomyText(line, .subheadline, tone: .secondary, numeric: true)
                .padding(.top, -T.Space.s4)
                .accessibilityIdentifier("errands-left")
        }
        if list.isEmpty {
            DomyEmptyState(
                icon: IconPaths.tabBasket,
                title: "還沒有要幫買的",
                message: "朋友家人託你買的東西記在這裡，買到了點一下打勾。"
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("errands-empty")
        } else {
            ForEach(errandGroups(list), id: \.who) { (g: ErrandGroup) in
                groupSection(g, names)
            }
        }
        addCard(names)
    }

    /// 一個人一組。正在改的那一列換成改的那幾格
    private func groupSection(_ g: ErrandGroup, _ names: [String]) -> some View {
        DomySection(g.title) {
            ForEach(g.items, id: \.id) { (x: Errand) in
                if editing == x.id {
                    editor(x, names)
                } else {
                    ErrandRow(x: x, onToggle: { toggle(x) }, onEdit: { startEdit(x) })
                }
            }
        }
    }

    /// 加一樣：買什麼一定要寫，其他可以不填
    private func addCard(_ names: [String]) -> some View {
        Card {
            DomyText("加一樣", .headline)
                .accessibilityAddTraits(.isHeader)
            ErrandFields(draft: $draft, names: names, tag: "errand")
            DomyButton("加進代購", disabled: draftBlank(draft), fullWidth: true) {
                add()
            }
            .accessibilityIdentifier("errand-add")
        }
    }

    /// 改一列：存起來、刪掉、不改了
    private func editor(_ x: Errand, _ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            ErrandFields(draft: $edit, names: names, tag: "errand-change")
            PairLayout(spacing: T.Space.s2) {
                DomyButton("存起來", variant: .secondary, size: .compact, disabled: draftBlank(edit), fullWidth: true) {
                    saveEdit(x)
                }
                .accessibilityIdentifier("errand-save")
                DomyButton("刪掉", variant: .destructive, size: .compact, fullWidth: true) {
                    remove(x)
                }
                .accessibilityIdentifier("errand-delete")
            }
            DomyButton("不改了", variant: .plain, size: .compact, fullWidth: true) {
                editing = nil
            }
            .accessibilityIdentifier("errand-cancel")
        }
        .padding(.vertical, T.Space.s3)
    }

    /* ---------- 改資料（都能復原） ---------- */

    private func add() {
        let x: ErrandDraft = draft
        if draftBlank(x) { return }
        Haptic.notify(.success)
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let added = addErrand(&trip, x.who, x.what, x.qty, x.note) else { return nil }
            d.trip = trip
            return "「\(added.what)」加進代購了。"
        }
        // 同一個人常常託好幾樣：誰託的留著，其他清掉
        draft = ErrandDraft(who: x.who, what: "", qty: 1, note: "")
    }

    private func toggle(_ x: Errand) {
        Haptic.select()
        let id: String = x.id
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let now = toggleErrand(&trip, id) else { return nil }
            d.trip = trip
            return now.done ? "「\(now.what)」買到了。" : "「\(now.what)」改回還沒買。"
        }
    }

    private func startEdit(_ x: Errand) {
        edit = ErrandDraft(who: x.who, what: x.what, qty: x.qty, note: x.note ?? "")
        editing = x.id
    }

    /// 存起來。跟原本一樣就不留一步
    private func saveEdit(_ x: Errand) {
        let e: ErrandDraft = edit
        let id: String = x.id
        editing = nil
        guard let input = cleanErrand(e.who, e.what, e.qty, e.note) else { return }
        if input.who == x.who && input.what == x.what && input.qty == x.qty && input.note == x.note { return }
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let now = editErrand(&trip, id, e.who, e.what, e.qty, e.note) else { return nil }
            d.trip = trip
            return "「\(now.what)」改好了。"
        }
    }

    private func remove(_ x: Errand) {
        Haptic.impact(.light)
        let id: String = x.id
        editing = nil
        store.act(undoable: true) { (d: inout AppState) -> String? in
            guard var trip = d.trip else { return nil }
            guard let gone = removeErrand(&trip, id) else { return nil }
            d.trip = trip
            return "「\(gone.what)」刪掉了。"
        }
    }
}

/// 一列：前面的圈點一下勾買到（整列都點得到），右邊「改」打開改的那幾格
private struct ErrandRow: View {
    let x: Errand
    let onToggle: () -> Void
    let onEdit: () -> Void

    private var spoken: String {
        guard let note = errandNote(x) else { return x.what }
        return "\(x.what)，\(note)"
    }

    var body: some View {
        HStack(spacing: T.Space.s2) {
            Button(action: onToggle) {
                rowContent
            }
            .buttonStyle(RowPressStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            .accessibilityValue(x.done ? "買到了" : "還沒買")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("errand-row-\(x.id)")
            DomyButton("改", variant: .plain, size: .compact, label: "改「\(x.what)」") {
                onEdit()
            }
            .accessibilityIdentifier("errand-edit-\(x.id)")
        }
        .padding(.leading, -T.Space.s4)
    }

    private var whatTone: TextTone {
        return x.done ? TextTone.secondary : TextTone.primary
    }

    private var rowContent: some View {
        HStack(alignment: .top, spacing: T.Space.s3) {
            Image(systemName: x.done ? "checkmark.circle.fill" : "circle")
                .font(T.TypeScale.title2.font)
                .foregroundStyle(x.done ? C.accent : C.fieldBorder)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: T.Space.s1) {
                DomyText(x.what, .body, tone: whatTone)
                if let note = errandNote(x) {
                    DomyText(note, .footnote, tone: .secondary)
                }
            }
            .fillLeading()
        }
        .padding(.vertical, T.Space.s3)
        .frame(minHeight: T.Size.row)
        .padding(.leading, T.Space.s4)
        .contentShape(Rectangle())
    }
}

/// 加一樣、改一樣共用的幾格：買什麼、誰託的（寫過的名字點一下就填好）、幾個、備註。
/// tag 是無障礙識別碼的開頭，UI 測試用
private struct ErrandFields: View {
    @Binding var draft: ErrandDraft
    let names: [String]
    let tag: String

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            DomyTextField("買什麼", text: $draft.what, placeholder: "例如：面膜")
                .accessibilityIdentifier("\(tag)-what")
                .onChange(of: draft.what) { (_: String, text: String) in
                    if let cut = cutOver(text, ERRAND_WHAT_MAX) { draft.what = cut }
                }
            whoField
            Stepper(value: $draft.qty, in: 1...ERRAND_QTY_MAX) {
                DomyText("幾個：\(draft.qty)", numeric: true)
            }
            .accessibilityIdentifier("\(tag)-qty")
            DomyTextField("備註（可以不填）", text: $draft.note, placeholder: "例如：顏色、尺寸、在哪買")
                .accessibilityIdentifier("\(tag)-note")
                .onChange(of: draft.note) { (_: String, text: String) in
                    if let cut = cutOver(text, ERRAND_NOTE_MAX) { draft.note = cut }
                }
        }
    }

    private var whoTyped: String {
        return draft.who.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var whoField: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            DomyTextField("誰託的（可以不填）", text: $draft.who, placeholder: "例如：媽媽")
                .accessibilityIdentifier("\(tag)-who")
                .onChange(of: draft.who) { (_: String, text: String) in
                    if let cut = cutOver(text, ERRAND_WHO_MAX) { draft.who = cut }
                }
            if !names.isEmpty {
                ChipRow {
                    ForEach(names, id: \.self) { (name: String) in
                        Chip(name, selected: whoTyped == name, onSurface: true) {
                            draft.who = name
                        }
                    }
                }
            }
        }
    }
}
