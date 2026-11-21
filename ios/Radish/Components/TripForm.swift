// 一趟的基本資料，一頁填完：去哪、哪天、幾天、幾點到幾點走、幾個人、住哪、名稱、封面。
// 開一趟時填一次，排好之後在「行程設定」可以回來改。用講的改行程時 AI 也看得到這些。
// 對應 mobile/src/components/TripForm.tsx。
import SwiftUI

private let DAYS: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 12, 14]
private let ARRIVE: [(Part, String)] = [(.am, "中午前"), (.pm, "下午"), (.eve, "晚上")]
private let LEAVE: [(Part, String)] = [(.am, "上午"), (.pm, "下午"), (.eve, "晚上")]
private let PEOPLE: [(Int, String)] = [(1, "我一個人"), (2, "兩個人"), (4, "三四個人")]
/// TS 是 Object.keys(HOTEL)，順序是 C、D、G、I，跟 BaseKey 宣告的順序一樣
private let BASES: [BaseKey] = BaseKey.allCases
private let COVER_H: CGFloat = T.Size.heroButton * 2  // domy-ignore: 封面照的高度，只有這裡用
private let STAY_NAME_MAX: Int = 40
private let TRIP_NAME_MAX: Int = 20

struct TripFormValue: Equatable {
    var name: String = ""
    var cover: String?
    var start: String?
    var days: Int?
    var arrive: Part?
    var leave: Part?
    var people: Int?
    /// 住哪一帶。baseDone 為 true 而 base 是空的，代表「還沒決定」
    var base: BaseKey?
    var baseDone: Bool = false
    var stayName: String = ""
    var tweaks: [Tweak] = []
}

extension TripFormValue {
    /// TS 的 form.stayName.trim() || undefined
    var cleanStayName: String? {
        let text: String = stayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// TS 的 form.name.trim() || undefined
    var cleanName: String? {
        let text: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// TS 的 form.tweaks.length ? form.tweaks : undefined
    var cleanTweaks: [Tweak]? {
        return tweaks.isEmpty ? nil : tweaks
    }
}

func blankForm() -> TripFormValue {
    return TripFormValue()
}

func formOf(_ t: Trip) -> TripFormValue {
    return TripFormValue(
        name: t.name ?? "",
        cover: t.cover,
        start: t.start,
        days: t.days,
        arrive: t.arrive,
        leave: t.leave,
        people: t.people,
        base: t.base,
        baseDone: true,
        stayName: t.stayName ?? "",
        tweaks: t.tweaks ?? []
    )
}

/// 還沒填的必填欄位，用來告訴使用者為什麼還不能按
func missingOf(_ v: TripFormValue) -> [String] {
    var out: [String] = []
    if (v.start ?? "").isEmpty { out.append("出發日") }
    if (v.days ?? 0) == 0 { out.append("去幾天") }
    if v.arrive == nil { out.append("第一天幾點到") }
    if v.leave == nil { out.append("最後一天幾點走") }
    if (v.people ?? 0) == 0 { out.append("幾個人") }
    if !v.baseDone { out.append("住哪一帶") }
    return out
}

/// 一個欄位：小標在上，內容在下
private struct FormField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s2) {
            FieldLabel(label)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TripForm: View {
    @Environment(AppStore.self) private var store
    @Binding var value: TripFormValue
    let minStart: String
    let fallbackBase: BaseKey

    init(value: Binding<TripFormValue>, minStart: String, fallbackBase: BaseKey) {
        self._value = value
        self.minStart = minStart
        self.fallbackBase = fallbackBase
    }

    /// 出發日那一欄的小標
    private var startLabel: String {
        if let start = value.start, !start.isEmpty {
            return "出發日：\(fmtDay(start))"
        }
        return "出發日"
    }

    /// 去幾天那一欄的小標：出發日和天數都有了，就順便講哪天回來
    private var daysLabel: String {
        if let start = value.start, !start.isEmpty, let days = value.days, days != 0 {
            let end: String = fmtDay(addDays(start, days - 1))
            return "去幾天：\(end)回來"
        }
        return "去幾天"
    }

    private var baseNote: String {
        let head: String = "每天的路線會從住的地方出發、再回來。"
        if value.baseDone && value.base == nil {
            return head + "還沒決定的話，先當作住\(HOTEL[need: fallbackBase].n)。"
        }
        return head
    }

    private var stayNameText: Binding<String> {
        return Binding<String>(
            get: { value.stayName },
            set: { (text: String) in value.stayName = String(text.prefix(STAY_NAME_MAX)) }
        )
    }

    private var nameText: Binding<String> {
        return Binding<String>(
            get: { value.name },
            set: { (text: String) in value.name = String(text.prefix(TRIP_NAME_MAX)) }
        )
    }

    private func toggleTweak(_ k: Tweak) {
        if value.tweaks.contains(k) {
            value.tweaks = value.tweaks.filter { (x: Tweak) -> Bool in x != k }
        } else {
            value.tweaks = value.tweaks + [k]
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s5) {
            whereField
            startField
            daysField
            arriveField
            leaveField
            peopleField
            baseField
            tweakField
            stayNameField
            nameField
            coverField
        }
    }

    private var whereField: some View {
        FormField("去哪") {
            ChipRow {
                Chip("首爾", selected: true)
            }
            DomyText("現在只有首爾，其他城市之後開放。", .footnote, tone: .secondary)
        }
    }

    private var startField: some View {
        FormField(startLabel) {
            CalendarGrid(min: minStart, value: value.start) { (iso: String) in
                value.start = iso
            }
        }
    }

    private var daysField: some View {
        FormField(daysLabel) {
            ChipRow {
                ForEach(DAYS, id: \.self) { (d: Int) in
                    Chip("\(d) 天", selected: value.days == d) {
                        value.days = d
                    }
                    .accessibilityIdentifier("days-\(d)")
                }
            }
        }
    }

    private var arriveField: some View {
        FormField("第一天幾點到") {
            ChipRow {
                ForEach(ARRIVE.indices, id: \.self) { (index: Int) in
                    let option: (Part, String) = ARRIVE[index]
                    Chip(option.1, selected: value.arrive == option.0) {
                        value.arrive = option.0
                    }
                    .accessibilityIdentifier("arrive-\(option.0.rawValue)")
                }
            }
        }
    }

    private var leaveField: some View {
        FormField("最後一天幾點走") {
            ChipRow {
                ForEach(LEAVE.indices, id: \.self) { (index: Int) in
                    let option: (Part, String) = LEAVE[index]
                    Chip(option.1, selected: value.leave == option.0) {
                        value.leave = option.0
                    }
                    .accessibilityIdentifier("leave-\(option.0.rawValue)")
                }
            }
        }
    }

    private var peopleField: some View {
        FormField("幾個人去") {
            ChipRow {
                ForEach(PEOPLE.indices, id: \.self) { (index: Int) in
                    let option: (Int, String) = PEOPLE[index]
                    Chip(option.1, selected: value.people == option.0) {
                        value.people = option.0
                    }
                    .accessibilityIdentifier("people-\(option.0)")
                }
            }
        }
    }

    private var baseField: some View {
        FormField("住哪一帶") {
            ChipRow {
                ForEach(BASES, id: \.self) { (k: BaseKey) in
                    Chip(HOTEL[need: k].n, selected: value.baseDone && value.base == k) {
                        value.base = k
                        value.baseDone = true
                    }
                    .accessibilityIdentifier("base-\(k.rawValue)")
                }
                Chip("還沒決定", selected: value.baseDone && value.base == nil) {
                    value.base = nil
                    value.baseDone = true
                }
                .accessibilityIdentifier("base-none")
            }
            DomyText(baseNote, .footnote, tone: .secondary)
        }
    }

    private var tweakField: some View {
        FormField("這趟有什麼不一樣（可以不選）") {
            ChipRow {
                ForEach(TWEAKS, id: \.self) { (k: Tweak) in
                    Chip(TWEAK_TEXT[need: k].name, selected: value.tweaks.contains(k)) {
                        toggleTweak(k)
                    }
                    .accessibilityIdentifier("tweak-\(k.rawValue)")
                }
            }
            if !value.tweaks.isEmpty {
                tweakNotes
            }
            DomyText("只改這一趟，不會動到「我」裡存好的偏好。", .footnote, tone: .secondary)
        }
    }

    private var tweakNotes: some View {
        let picked: [Tweak] = TWEAKS.filter { (k: Tweak) -> Bool in value.tweaks.contains(k) }
        return VStack(alignment: .leading, spacing: T.Space.s1) {
            FieldLabel("這趟會改成")
            ForEach(picked, id: \.self) { (k: Tweak) in
                let label: LabelText = TWEAK_TEXT[need: k]
                DomyText("\(label.name)：\(label.note)。", .subheadline)
            }
        }
    }

    private var stayNameField: some View {
        DomyTextField(
            "住宿名稱（可以不填）",
            text: stayNameText,
            placeholder: "例如：明洞某某飯店",
            helper: "先記著，還不會用它算路線。路線照上面選的那一帶估。"
        )
    }

    private var nameField: some View {
        DomyTextField(
            "幫這趟取個名字（可以不填）",
            text: nameText,
            placeholder: "例如：跟媽媽的首爾",
            helper: "不填的話就叫「首爾幾天」。"
        )
    }

    private var coverField: some View {
        FormField("封面照片（可以不放）") {
            if let cover = value.cover {
                CoverPhoto(ref: cover)
            }
            HStack(spacing: T.Space.s2) {
                PhotoAddButton(
                    value.cover != nil ? "換一張" : "從相簿挑一張",
                    onPicked: { (name: String) in value.cover = name },
                    onFailed: { store.say("這張照片放不進來，換一張試試。") }
                )
                if value.cover != nil {
                    DomyButton("不放了", variant: .plain, size: .compact) {
                        value.cover = nil
                    }
                }
            }
            DomyText("會顯示在「旅行」分頁這一趟的旁邊。照片存在這支手機裡，不會上傳。", .footnote, tone: .secondary)
        }
    }
}

/// 封面照片：整列寬、固定高度，裁滿。檔案讀不到時顯示灰底，不讓版面跳掉
private struct CoverPhoto: View {
    let ref: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous)
        C.surfaceMuted
            .frame(maxWidth: .infinity)
            .frame(height: COVER_H)
            .overlay {
                if let image = PhotoStore.image(ref) {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("這趟的封面照片")
            .accessibilityAddTraits(.isImage)
    }
}
