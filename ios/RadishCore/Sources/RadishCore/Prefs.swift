// 偏好裡會改變排法的幾件事：這趟臨時調整、從行程學到的「以後都不排」、過敏告知卡。
// 純函式，不碰畫面。Plan.swift 排行程時會用這裡的東西。照 mobile/src/domain/prefs.ts 搬。
import Foundation

private let FOOD_KINDS: [FoodKind] = [.street, .local, .famous, .fine]
private let SAVE_BUDGET: Double = 1000

/// 這趟實際拿來排的偏好：平常的你，加上這趟的臨時調整。不會改到傳進來的那份
func tripSettings(_ st: Settings, _ tweaks: [Tweak]?) -> Settings {
    guard let tw = tweaks, !tw.isEmpty else { return st }
    var out: Settings = st
    if tw.contains(.elder) {
        out.walk = .less
        if !out.body.contains(.stairs) { out.body.append(.stairs) }
        if out.pace == .fast { out.pace = .mid }
    }
    if tw.contains(.easy) {
        out.pace = out.pace == .fast ? Pace.mid : Pace.slow
    }
    if tw.contains(.save) {
        out.food[.fine] = 0
        let famous: Int = out.food[.famous] ?? 0
        out.food[.famous] = min(famous, 1)
        out.stay = .cheap
        out.budget = min(out.budget, SAVE_BUDGET)
    }
    return out
}

/* ---------- 從行程學到的 ---------- */

/// TS 的 Bannable 只拿 id、c、f 三欄，Place 和 Stop 都走這裡。
/// 記的是拆開前的舊代號（p4），拆出來的每一間都不排；記的是其中一間，就只擋那一間
private func bannedBy(_ id: String, _ c: Cat, _ f: FoodKind?, _ st: Settings) -> Bool {
    for l in st.learned {
        switch l.kind {
        case .place:
            if l.key == id || l.key == placeGroup(id) { return true }
        case .cat:
            if l.key == c.rawValue { return true }
        case .food:
            if c == .eat, let kind = f, l.key == kind.rawValue { return true }
        }
    }
    return false
}

/// 這個地方是不是使用者說過以後都不排的
func banned(_ p: Place, _ st: Settings) -> Bool {
    return bannedBy(p.id, p.c, p.f, st)
}

func banned(_ p: Stop, _ st: Settings) -> Bool {
    return bannedBy(p.id, p.c, p.f, st)
}

func bannedFood(_ st: Settings) -> Set<FoodKind> {
    var out: Set<FoodKind> = []
    for l in st.learned where l.kind == .food {
        if let k = FoodKind(rawValue: l.key) { out.insert(k) }
    }
    return out
}

/// TS 的 Pick<Learned, 'kind' | 'key' | 'n'>
struct LearnChoice: Hashable, Sendable {
    var kind: LearnKind
    var key: String
    var n: String
}

/// 拿掉這一站時，可以順便記成「以後都不排」的選項。自己加的、AI 加的站不在候選裡，沒有東西可以記
func learnChoices(_ it: Stop, _ st: Settings) -> [LearnChoice] {
    if it.mine == true || it.ai == true || it.a == nil { return [] }
    var out: [LearnChoice] = [LearnChoice(kind: .place, key: it.id, n: it.n)]
    if it.c != .eat {
        out.append(LearnChoice(kind: .cat, key: it.c.rawValue, n: CAT[need: it.c]))
    } else if let f = it.f {
        // 吃的照種類記。只剩這一種還在吃的話不給記，不然晚餐排不出來
        let no: Set<FoodKind> = bannedFood(st)
        let left: [FoodKind] = FOOD_KINDS.filter { (k: FoodKind) -> Bool in
            return (st.food[k] ?? 0) > 0 && !no.contains(k)
        }
        if left.count > 1 && left.contains(f) {
            out.append(LearnChoice(kind: .food, key: f.rawValue, n: FOOD[need: f].name))
        }
    }
    return out.filter { (c: LearnChoice) -> Bool in
        return !st.learned.contains { (l: Learned) -> Bool in l.kind == c.kind && l.key == c.key }
    }
}

private var learnSeq: Int = 0

func learn(_ st: inout Settings, _ c: LearnChoice, _ source: String) -> Learned {
    let ms: Int = Int(Date().timeIntervalSince1970 * 1000)
    let id: String = "l" + String(ms, radix: 36) + String(learnSeq, radix: 36)
    learnSeq += 1
    let x: Learned = Learned(id: id, kind: c.kind, key: c.key, n: c.n, source: source)
    let others: [Learned] = st.learned.filter { (l: Learned) -> Bool in
        return !(l.kind == c.kind && l.key == c.key)
    }
    st.learned = [x] + others
    return x
}

func unlearn(_ st: inout Settings, _ id: String) -> Learned? {
    let found: Learned? = st.learned.first { (l: Learned) -> Bool in l.id == id }
    guard let x = found else { return nil }
    st.learned = st.learned.filter { (l: Learned) -> Bool in l.id != id }
    return x
}

private func learnedLine(_ kind: LearnKind, _ n: String) -> String {
    return kind == .place ? "不排「\(n)」" : "不排「\(n)」這一類"
}

func learnedText(_ l: Learned) -> String {
    return learnedLine(l.kind, l.n)
}

func learnedText(_ l: LearnChoice) -> String {
    return learnedLine(l.kind, l.n)
}

/* ---------- 天氣和身體 ---------- */

/// TS 的 'hot' | 'cold' | null
enum Season: String, Sendable {
    case hot, cold
}

/// 出發那個月在首爾算熱還是冷。只看月份，不是天氣預報
func seasonOf(_ start: String) -> Season? {
    // TS 是 Number(start.slice(5, 7))：空字串算 0，不是數字的算 NaN（兩邊都不成立）
    let chars: [Character] = Array(start)
    var piece: String = ""
    if chars.count > 5 {
        let end: Int = min(7, chars.count)
        piece = String(chars[5..<end])
    }
    let trimmed: String = piece.trimmingCharacters(in: .whitespacesAndNewlines)
    var m: Int = 0
    if !trimmed.isEmpty {
        guard let v = Int(trimmed) else { return nil }
        m = v
    }
    if m >= 6 && m <= 9 { return Season.hot }
    if m == 12 || m <= 2 { return Season.cold }
    return nil
}

/// 大部分時間在戶外的地方：公園散步那一類，和近郊
func outdoor(_ p: Place) -> Bool {
    return p.c == .nature || p.a == .J
}

func outdoor(_ p: Stop) -> Bool {
    return p.c == .nature || p.a == AreaKey.J
}

/* ---------- 過敏告知卡 ---------- */
struct AllergyCard: Hashable, Sendable {
    var kr: String
    var zh: String
}

/// 給店員看的韓文告知卡。韓文是照常見說法寫的，還沒請懂韓文的人核對
func allergyCard(_ list: [String]) -> AllergyCard? {
    let hit: [Allergen] = ALLERGENS.filter { (a: Allergen) -> Bool in list.contains(a.n) }
    if hit.isEmpty { return nil }
    let krNames: [String] = hit.map { (a: Allergen) -> String in a.kr }
    let zhNames: [String] = hit.map { (a: Allergen) -> String in a.n }
    let kr: String = krNames.joined(separator: ", ")
    let zh: String = zhNames.joined(separator: "、")
    return AllergyCard(
        kr: "저는 음식 알레르기가 있습니다.\n\(kr)\n을(를) 먹으면 안 됩니다.\n이 음식에 들어 있나요?\n육수나 소스에 조금 들어간 것도 안 됩니다.",
        zh: "我有食物過敏，不能吃：\(zh)。請問這道菜裡面有嗎？湯底或醬料裡只有一點點也不行。"
    )
}

func catName(_ k: Cat) -> String {
    return CAT[need: k]
}
