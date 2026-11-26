// 代購清單：別人託這趟幫買的東西。新增、改、勾買到、刪掉、排順序、算還差幾樣。
// 都是直接改傳進來那份行程的純函式，由畫面包在 store.act(undoable: true) 裡呼叫。mobile/ 沒有對應的檔。
// 不算進花費，也不記價錢（定稿不做記帳）。資料型別 Errand 在 Models.swift，重排帶過去在 Spend.swift 的 replanTrip。
import Foundation

/// 沒寫是誰託的，那幾樣放在這一組
let ERRAND_NO_WHO: String = "沒寫是誰"
/// 幾個：最少 1，最多 99
let ERRAND_QTY_MAX: Int = 99
/// 每一格最多幾個字，超過的切掉
let ERRAND_WHAT_MAX: Int = 40
let ERRAND_WHO_MAX: Int = 20
let ERRAND_NOTE_MAX: Int = 80

/// 清乾淨的一列：去頭尾空白、切到字數上限、幾個夾在 1 到 99。what 是空的回 nil（不收）
struct ErrandInput: Equatable, Sendable {
    var who: String
    var what: String
    var qty: Int
    var note: String?
}

/// 去頭尾空白，再切到 limit 個字
private func errandText(_ raw: String, _ limit: Int) -> String {
    let trimmed: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= limit { return trimmed }
    let cut: String = String(trimmed.prefix(limit))
    return cut.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// 使用者打的四格變成要存的樣子。買什麼沒寫就不收
func cleanErrand(_ who: String, _ what: String, _ qty: Int, _ note: String?) -> ErrandInput? {
    let item: String = errandText(what, ERRAND_WHAT_MAX)
    if item.isEmpty { return nil }
    let person: String = errandText(who, ERRAND_WHO_MAX)
    let count: Int = min(ERRAND_QTY_MAX, max(1, qty))
    let memo: String = errandText(note ?? "", ERRAND_NOTE_MAX)
    return ErrandInput(who: person, what: item, qty: count, note: memo.isEmpty ? nil : memo)
}

/// 加一列，接在最後面（照新增順序）。買什麼沒寫回 nil、什麼都不動
@discardableResult
func addErrand(_ t: inout Trip, _ who: String, _ what: String, _ qty: Int = 1, _ note: String? = nil) -> Errand? {
    guard let input = cleanErrand(who, what, qty, note) else { return nil }
    let x: Errand = Errand(
        id: newId("e"), who: input.who, what: input.what, qty: input.qty, note: input.note, done: false)
    var list: [Errand] = t.errands ?? []
    list.append(x)
    t.errands = list
    return x
}

/// 改一列：誰託的、買什麼、幾個、備註。位置和買到了沒都不變。找不到、買什麼改成空的回 nil、什麼都不動
@discardableResult
func editErrand(
    _ t: inout Trip, _ id: String, _ who: String, _ what: String, _ qty: Int, _ note: String?
) -> Errand? {
    guard var list = t.errands else { return nil }
    let found: Int? = list.firstIndex { (x: Errand) -> Bool in x.id == id }
    guard let i = found else { return nil }
    guard let input = cleanErrand(who, what, qty, note) else { return nil }
    var x: Errand = list[i]
    x.who = input.who
    x.what = input.what
    x.qty = input.qty
    x.note = input.note
    list[i] = x
    t.errands = list
    return x
}

/// 勾買到，或取消買到。回改完的那一列；找不到回 nil
@discardableResult
func toggleErrand(_ t: inout Trip, _ id: String) -> Errand? {
    guard var list = t.errands else { return nil }
    let found: Int? = list.firstIndex { (x: Errand) -> Bool in x.id == id }
    guard let i = found else { return nil }
    var x: Errand = list[i]
    x.done = !x.done
    list[i] = x
    t.errands = list
    return x
}

/// 刪掉一列。刪到沒有了就變回 nil。回刪掉的那一列；找不到回 nil、什麼都不動
@discardableResult
func removeErrand(_ t: inout Trip, _ id: String) -> Errand? {
    guard let list = t.errands else { return nil }
    let found: Errand? = list.first { (x: Errand) -> Bool in x.id == id }
    guard let gone = found else { return nil }
    let left: [Errand] = list.filter { (x: Errand) -> Bool in x.id != id }
    t.errands = left.isEmpty ? nil : left
    return gone
}

/// 還沒買的在前、買到的在後；同一邊照新增順序。Swift 的 sort 不保證穩定，所以把原本的位置當第二個鍵
func sortedErrands(_ list: [Errand]) -> [Errand] {
    var indexed: [(i: Int, x: Errand)] = []
    for (i, x) in list.enumerated() {
        indexed.append((i: i, x: x))
    }
    let sorted: [(i: Int, x: Errand)] = indexed.sorted { (a: (i: Int, x: Errand), b: (i: Int, x: Errand)) -> Bool in
        if a.x.done != b.x.done { return !a.x.done }
        return a.i < b.i
    }
    return sorted.map { (p: (i: Int, x: Errand)) -> Errand in p.x }
}

/// 還差幾樣：還沒買到的有幾列（一列算一樣，不管幾個）
func errandsLeft(_ list: [Errand]) -> Int {
    return list.filter { (x: Errand) -> Bool in !x.done }.count
}

/// 畫面上寫的誰託的。沒寫就是「沒寫是誰」
func errandWho(_ x: Errand) -> String {
    let name: String = x.who.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? ERRAND_NO_WHO : name
}

/// 照誰託的分的一組。who 是存的名字（沒寫是空字串），title 是畫面上寫的
struct ErrandGroup: Equatable, Sendable {
    let who: String
    let title: String
    let items: [Errand]
}

/// 照誰託的分組。還有沒買的組在前、都買到的組在後；同一邊照那個人第一次出現的順序，
/// 沒寫是誰的那一組放在同一邊的最後。組裡照 sortedErrands
func errandGroups(_ list: [Errand]) -> [ErrandGroup] {
    var keys: [String] = []
    var byKey: [String: [Errand]] = [:]
    for x in list {
        let key: String = x.who.trimmingCharacters(in: .whitespacesAndNewlines)
        if byKey[key] == nil {
            keys.append(key)
            byKey[key] = []
        }
        byKey[key]?.append(x)
    }
    var open: [ErrandGroup] = []
    var closed: [ErrandGroup] = []
    var openNoWho: ErrandGroup? = nil
    var closedNoWho: ErrandGroup? = nil
    for key in keys {
        let items: [Errand] = sortedErrands(byKey[key] ?? [])
        let group: ErrandGroup = ErrandGroup(who: key, title: key.isEmpty ? ERRAND_NO_WHO : key, items: items)
        let allDone: Bool = errandsLeft(items) == 0
        if key.isEmpty {
            if allDone { closedNoWho = group } else { openNoWho = group }
        } else if allDone {
            closed.append(group)
        } else {
            open.append(group)
        }
    }
    if let g = openNoWho { open.append(g) }
    if let g = closedNoWho { closed.append(g) }
    return open + closed
}

/// 最上面那一行。沒有東西回 nil（畫面放空白說明）
func errandsLine(_ list: [Errand]) -> String? {
    if list.isEmpty { return nil }
    let left: Int = errandsLeft(list)
    if left == 0 { return "都買到了，一共 \(list.count) 樣。" }
    return "還差 \(left) 樣沒買，一共 \(list.count) 樣。"
}

/// 已經寫過的名字，照第一次出現的順序，不重複。加一樣的時候點一下就填好
func errandNames(_ list: [Errand]) -> [String] {
    var out: [String] = []
    for x in list {
        let name: String = x.who.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || out.contains(name) { continue }
        out.append(name)
    }
    return out
}

/// 一列的第二行：幾個、備註。只有一個又沒備註回 nil
func errandNote(_ x: Errand) -> String? {
    var bits: [String] = []
    if x.qty > 1 { bits.append("\(x.qty) 個") }
    if let note = x.note, !note.isEmpty { bits.append(note) }
    return bits.isEmpty ? nil : bits.joined(separator: "・")
}
