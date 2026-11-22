// AI 改行程的權限。AI 碰不到資料，只能回一串 op；每一種 op 在這張表上有等級：
// 直接改（說了就改，可以復原）、要確認（app 跳一張卡，使用者按「套用」才改）。
// 表上沒有的 op 一律不做。拔起來、那一句、照片、自己記的花費、核對過的事實，根本沒有 op 能碰到。
// 這個檔是 SwiftUI 版才有的，mobile/ 沒有對應的 TS。
import Foundation

enum OpLevel: String, Codable, Sendable {
    case direct
    case confirm
}

/// 權限表。新增一種 op：在這裡給等級、在 chatApplyOne 寫怎麼做、在 opLine 寫怎麼講、補測試
let OP_LEVELS: [String: OpLevel] = [
    "move": .direct,
    "swapParts": .direct,
    "swapDays": .direct,
    "remove": .direct,
    "add": .direct,
    "replace": .direct,
    "rest": .direct,
    "setTweak": .confirm,
]

/// 這個時段裡有沒有使用者自己加的站
private func permitSlotMine(_ t: Trip, _ day: Int, _ part: Part) -> Bool {
    return t.slots.contains { (s: Slot) -> Bool in
        return s.day == day && s.part == part && s.items.contains { (it: Stop) -> Bool in it.mine == true }
    }
}

/// JSON 來的天數。JSONSerialization 給的是 NSNumber，測試直接給的是 Int
private func permitDay(_ v: Any?) -> Int? {
    if let n = v as? Int { return n }
    if let n = v as? NSNumber {
        let d: Double = n.doubleValue
        if d == d.rounded() && abs(d) < 10000 { return Int(d) }
    }
    return nil
}

/// on 沒給當成 true
func permitOn(_ v: Any?) -> Bool {
    guard let v = v else { return true }
    if let b = v as? Bool { return b }
    if let n = v as? NSNumber { return n.boolValue }
    return true
}

/// 這一步動不動到使用者自己加的站
func opTouchesMine(_ t: Trip, _ o: [String: Any]) -> Bool {
    guard let op = o["op"] as? String else { return false }
    if op == "move" || op == "remove" || op == "replace" {
        guard let id = o["id"] as? String, let x = findItem(t, id) else { return false }
        return x.it.mine == true
    }
    if op == "swapParts" {
        guard let day = permitDay(o["day"]) else { return false }
        for raw in [o["a"], o["b"]] {
            if let w = raw as? String, let p = Part(rawValue: w), permitSlotMine(t, day, p) { return true }
        }
        return false
    }
    if op == "swapDays" {
        for raw in [o["a"], o["b"]] {
            guard let day = permitDay(raw) else { continue }
            for p in PARTS where permitSlotMine(t, day, p) { return true }
        }
        return false
    }
    return false
}

/// 這一步的等級。表上沒有的回 nil（不做）。動到自己加的站，一律升成要確認
func opLevel(_ t: Trip, _ o: [String: Any]) -> OpLevel? {
    guard let op = o["op"] as? String, let base = OP_LEVELS[op] else { return nil }
    if base == .direct && opTouchesMine(t, o) { return OpLevel.confirm }
    return base
}

/// 把 AI 回的一串 op 分成直接改和要確認兩堆。不是物件、表上沒有的，留在直接改那堆，applyOps 照舊忽略或記一句
func splitOps(_ t: Trip, _ ops: Any?) -> (direct: [Any], confirm: [[String: Any]]) {
    var direct: [Any] = []
    var confirm: [[String: Any]] = []
    guard let list = ops as? [Any] else { return (direct: direct, confirm: confirm) }
    for raw in list.prefix(20) {
        var obj: [String: Any]? = raw as? [String: Any]
        if let typed = raw as? Op { obj = opJSON(typed) }
        if let o = obj, opLevel(t, o) == .confirm {
            confirm.append(o)
        } else {
            direct.append(raw)
        }
    }
    return (direct: direct, confirm: confirm)
}

/* ---------- 待確認的那幾步：存在對話裡，按了才套用 ---------- */

/// 存成 JSON 字串，才放得進 Codable 的 ChatMsg
func packOps(_ ops: [[String: Any]]) -> String {
    guard JSONSerialization.isValidJSONObject(ops),
        let data = try? JSONSerialization.data(withJSONObject: ops, options: [.sortedKeys]),
        let s = String(data: data, encoding: .utf8)
    else { return "[]" }
    return s
}

func unpackOps(_ s: String) -> [Any] {
    guard let data = s.data(using: .utf8),
        let obj = try? JSONSerialization.jsonObject(with: data, options: []),
        let list = obj as? [Any]
    else { return [] }
    return list
}

private func permitName(_ t: Trip, _ id: Any?) -> String {
    guard let id = id as? String, let x = findItem(t, id) else { return "那一站" }
    return "「\(x.it.n)」"
}

private func permitWhere(_ day: Any?, _ part: Any?) -> String {
    let d: String = permitDay(day).map { (n: Int) -> String in "第 \(n) 天" } ?? "某一天"
    var p: String = ""
    if let w = part as? String, let pp = Part(rawValue: w) { p = PART[need: pp] }
    return d + p
}

/// 確認卡上的一行：要改什麼，為什麼要你點頭
func opLine(_ t: Trip, _ o: [String: Any]) -> String {
    let op: String = (o["op"] as? String) ?? ""
    let mine: String = opTouchesMine(t, o) ? "（動到你自己加的站）" : ""
    switch op {
    case "move":
        return "\(permitName(t, o["id"]))移到\(permitWhere(o["day"], o["part"]))\(mine)"
    case "remove":
        return "拿掉\(permitName(t, o["id"]))，放進下次再來\(mine)"
    case "replace":
        var to: String = "別的地方"
        if let id = o["with"] as? String, let p = PLACES.first(where: { (q: Place) -> Bool in q.id == id }) {
            to = "「\(p.n)」"
        } else if let obj = o["with"] as? [String: Any], let n = obj["n"] as? String {
            to = "「\(n)」"
        }
        return "\(permitName(t, o["id"]))換成\(to)\(mine)"
    case "swapParts":
        var b: String = ""
        if let w = o["b"] as? String, let pp = Part(rawValue: w) { b = PART[need: pp] }
        return "\(permitWhere(o["day"], o["a"]))和\(b)對調\(mine)"
    case "swapDays":
        let a: String = permitDay(o["a"]).map { (n: Int) -> String in "\(n)" } ?? "?"
        let b: String = permitDay(o["b"]).map { (n: Int) -> String in "\(n)" } ?? "?"
        return "第 \(a) 天和第 \(b) 天整天對調\(mine)"
    case "setTweak":
        let name: String = tweakOf(o["tweak"]).map { (k: Tweak) -> String in TWEAK_TEXT[need: k].name } ?? "這個調整"
        let on: Bool = permitOn(o["on"])
        return on ? "這趟加上「\(name)」" : "這趟拿掉「\(name)」"
    default:
        return "改一個地方"
    }
}

func tweakOf(_ v: Any?) -> Tweak? {
    guard let w = v as? String else { return nil }
    return Tweak(rawValue: w)
}

/// 這趟加上或拿掉一個臨時調整。回沒做成的原因
func setTweak(_ t: inout Trip, _ v: Any?, _ on: Bool) -> String? {
    guard let k = tweakOf(v) else { return "沒有這種調整" }
    var list: [Tweak] = t.tweaks ?? []
    if on {
        if !list.contains(k) { list.append(k) }
    } else {
        list.removeAll { (x: Tweak) -> Bool in x == k }
    }
    t.tweaks = list.isEmpty ? nil : list
    return nil
}
