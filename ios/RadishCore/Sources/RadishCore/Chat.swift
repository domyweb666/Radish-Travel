// 用講的改行程。兩條路：
// 1. 有設定 AI_ENDPOINT → 把提示詞送到自己的後端（後端再轉給 AI），拿回 {reply, ops}
// 2. 沒設定 → 本機只聽得懂幾種固定說法
// 兩條路最後都走 applyOps，所以改動清單和復原是同一套。
// 照 mobile/src/domain/chat.ts 搬。Op、AiPlace 在 TS 是放在 types.ts 最後面，這裡放在這個檔。
import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/* ---------- 型別 ---------- */

/// AI 自己提的地點。每一欄都還沒核對過
struct AiPlace: Codable, Hashable {
    var n: String
    var kr: String?
    var c: String?
    var s: String?
    var tip: String?
    var lat: Double?
    var lng: Double?
}

/// TS 的 string | AiPlace：候選清單裡的代號，或 AI 自己提的地點
enum OpPlace: Hashable {
    case id(String)
    case place(AiPlace)
}

/// 改行程的一個動作。case 名字就是 JSON 裡 op 那一欄的字
enum Op: Hashable {
    case move(id: String, day: Int, part: Part)
    case swapParts(day: Int, a: Part, b: Part)
    case swapDays(a: Int, b: Int)
    case remove(id: String)
    case add(day: Int, part: Part, id: String?, place: AiPlace?)
    case replace(id: String, with: OpPlace)
    case rest(day: Int, part: Part, on: Bool)
}

/// ops 是還沒驗過的 JSON（[String: Any] 一條一條），所以這個型別不能自動 Codable、Equatable
struct BrainOut {
    var reply: String
    var ops: [Any]
    var regen: Bool?
}

let LOCAL_HINTS: [String] = ["第 2 天上午下午對調", "第 2 天跟第 3 天對調", "第 3 天輕鬆一點", "重排"]
let AI_HINTS: [String] = ["第 2 天上午下午對調", "第 3 天輕鬆一點", "多排一點咖啡廳", "有一天想整天逛街", "雨天備案是什麼"]

private let PART_WORD: [String: Part] = ["上午": .am, "下午": .pm, "晚上": .eve]

/* ---------- Op ↔ JSON ---------- */

private func chatPlaceJSON(_ p: AiPlace) -> [String: Any] {
    var out: [String: Any] = ["n": p.n]
    if let kr = p.kr { out["kr"] = kr }
    if let c = p.c { out["c"] = c }
    if let s = p.s { out["s"] = s }
    if let tip = p.tip { out["tip"] = tip }
    if let lat = p.lat { out["lat"] = lat }
    if let lng = p.lng { out["lng"] = lng }
    return out
}

/// 把一個 Op 寫成 JSON 的樣子（跟 AI 回來的格式一樣），applyOps 吃的就是這個
func opJSON(_ o: Op) -> [String: Any] {
    switch o {
    case .move(let id, let day, let part):
        return ["op": "move", "id": id, "day": day, "part": part.rawValue]
    case .swapParts(let day, let a, let b):
        return ["op": "swapParts", "day": day, "a": a.rawValue, "b": b.rawValue]
    case .swapDays(let a, let b):
        return ["op": "swapDays", "a": a, "b": b]
    case .remove(let id):
        return ["op": "remove", "id": id]
    case .add(let day, let part, let id, let place):
        var out: [String: Any] = ["op": "add", "day": day, "part": part.rawValue]
        if let id = id { out["id"] = id }
        if let place = place { out["place"] = chatPlaceJSON(place) }
        return out
    case .replace(let id, let with):
        var out: [String: Any] = ["op": "replace", "id": id]
        switch with {
        case .id(let other):
            out["with"] = other
        case .place(let place):
            out["with"] = chatPlaceJSON(place)
        }
        return out
    case .rest(let day, let part, let on):
        return ["op": "rest", "day": day, "part": part.rawValue, "on": on]
    }
}

/* ---------- 正規表示式的小工具 ---------- */

/// 第一個符合的地方。回每一組抓到的字（第 0 個是整段），沒抓到的那一組是 nil
private func chatMatch(_ pattern: String, _ text: String) -> [String?]? {
    guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
    let full: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let m = rx.firstMatch(in: text, options: [], range: full) else { return nil }
    var out: [String?] = []
    for i in 0..<m.numberOfRanges {
        let r: NSRange = m.range(at: i)
        if r.location == NSNotFound {
            out.append(nil)
        } else if let rr = Range(r, in: text) {
            out.append(String(text[rr]))
        } else {
            out.append(nil)
        }
    }
    return out
}

private func chatGroup(_ m: [String?], _ i: Int) -> String? {
    guard i >= 0 && i < m.count else { return nil }
    return m[i]
}

private func chatStrip(_ pattern: String, _ text: String) -> String {
    guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
    let full: NSRange = NSRange(text.startIndex..<text.endIndex, in: text)
    return rx.stringByReplacingMatches(in: text, options: [], range: full, withTemplate: "")
}

/// TS 的 +m[1]：抓到的一定是數字。位數多到裝不下的當成一個不存在的天數
private func chatInt(_ s: String) -> Int {
    return Int(s) ?? Int.max
}

/* ---------- 本機指令 ---------- */

private func chatFind(_ name: String, _ t: Trip) -> Found? {
    let k: String = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if k.isEmpty { return nil }
    for x in allItems(t) {
        if x.it.n.contains(k) { return x }
        let bare: String = chatStrip("（.*?）", x.it.n)
        // TS 的 includes('') 一定是 true
        if bare.isEmpty || k.contains(bare) { return x }
    }
    return nil
}

/// 沒接 AI 時的本機指令。聽不懂就老實說聽不懂
func localBrain(_ msg: String, _ t: Trip) -> BrainOut {
    if msg.contains("重排") || msg.contains("重新排") {
        return BrainOut(reply: "好，整趟重排一次。", ops: [], regen: true)
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*第\\s*([0-9]+)\\s*天.*(對調|交換|互換)", msg),
        let d1 = chatGroup(m, 1), let d2 = chatGroup(m, 2)
    {
        let op: Op = Op.swapDays(a: chatInt(d1), b: chatInt(d2))
        return BrainOut(reply: "第 \(d1) 天和第 \(d2) 天整天對調了。", ops: [opJSON(op)])
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*(對調|交換|互換)", msg), let d1 = chatGroup(m, 1) {
        let op: Op = Op.swapParts(day: chatInt(d1), a: Part.am, b: Part.pm)
        return BrainOut(reply: "第 \(d1) 天的上午和下午對調了。", ops: [opJSON(op)])
    }
    if let m = chatMatch("把?(.+?)(?:移|搬|挪|改|放)到?第\\s*([0-9]+)\\s*天\\s*(上午|下午|晚上)?", msg),
        let name = chatGroup(m, 1), let d2 = chatGroup(m, 2)
    {
        if let x = chatFind(name, t) {
            var part: Part = x.s.part
            if let word = chatGroup(m, 3), let said = PART_WORD[word] { part = said }
            let op: Op = Op.move(id: x.it.id, day: chatInt(d2), part: part)
            return BrainOut(reply: "「\(x.it.n)」移到第 \(d2) 天\(PART[need: part])了。", ops: [opJSON(op)])
        }
    }
    if let m = chatMatch("(?:不要|拿掉|刪掉|移除|不去)(.+)", msg), let rest = chatGroup(m, 1) {
        var name: String = rest.replacingOccurrences(of: "了", with: "")
        name = name.replacingOccurrences(of: "吧", with: "")
        name = name.replacingOccurrences(of: "。", with: "")
        if let x = chatFind(name, t) {
            let op: Op = Op.remove(id: x.it.id)
            return BrainOut(reply: "「\(x.it.n)」拿掉了，放進下次再來。", ops: [opJSON(op)])
        }
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*(輕鬆|少一點|太累|太滿)", msg), let d1 = chatGroup(m, 1) {
        let stops: [Found] = dayStops(t, chatInt(d1))
        let big: Found? = stops.first { (s: Found) -> Bool in s.it.s == .L }
        if let x = big ?? stops.first {
            let op: Op = Op.remove(id: x.it.id)
            return BrainOut(reply: "第 \(d1) 天拿掉「\(x.it.n)」，鬆一點。", ops: [opJSON(op)])
        }
    }
    return BrainOut(
        reply: "這一版還沒接上 AI，我只聽得懂幾種說法：「第 3 天上午下午對調」「第 2 天跟第 4 天對調」「把景福宮移到第 4 天上午」「不要樂天世界」「第 3 天輕鬆一點」「重排」。",
        ops: []
    )
}

/* ---------- 讀不可信的 JSON：照 JavaScript 的規則把值轉成數字、字、真假 ---------- */

/// 是不是 JSON 的 true／false。NSNumber 的 1 不算（Apple 平台上 NSNumber(1) as? Bool 會成功，所以要先看型別碼）
private func chatBool(_ v: Any) -> Bool? {
    if let n = v as? NSNumber {
        let code: String = String(cString: n.objCType)
        return (code == "c" || code == "B") ? n.boolValue : nil
    }
    if let b = v as? Bool { return b }
    return nil
}

/// TS 的 +x、Number(x)。nil 是 undefined
private func chatNum(_ v: Any?) -> Double {
    guard let v = v else { return Double.nan }
    if v is NSNull { return 0 }
    if let b = chatBool(v) { return b ? 1 : 0 }
    if let n = v as? NSNumber { return n.doubleValue }
    if let i = v as? Int { return Double(i) }
    if let d = v as? Double { return d }
    if let s = v as? String {
        let k: String = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if k.isEmpty { return 0 }
        return Double(k) ?? Double.nan
    }
    return Double.nan
}

/// 剛好是整數才回。2.5、NaN、太大的都對不到任何一天
private func chatWhole(_ d: Double) -> Int? {
    guard d.isFinite, d == d.rounded(), abs(d) < 1.0e15 else { return nil }
    return Int(d)
}

/// 數字放進字串裡的樣子：2 不是 2.0
private func chatNumText(_ d: Double) -> String {
    if d.isNaN { return "NaN" }
    if !d.isFinite { return d > 0 ? "Infinity" : "-Infinity" }
    if let i = chatWhole(d) { return String(i) }
    return String(d)
}

/// TS 的 String(x)、`${x}`
private func chatText(_ v: Any?) -> String {
    guard let v = v else { return "undefined" }
    if v is NSNull { return "null" }
    if let s = v as? String { return s }
    if let b = chatBool(v) { return b ? "true" : "false" }
    if v is NSNumber || v is Int || v is Double { return chatNumText(chatNum(v)) }
    if let list = v as? [Any] {
        let bits: [String] = list.map { (x: Any) -> String in x is NSNull ? "" : chatText(x) }
        return bits.joined(separator: ",")
    }
    return "[object Object]"
}

/// TS 的 String(x ?? '')
private func chatTextOrEmpty(_ v: Any?) -> String {
    guard let v = v else { return "" }
    if v is NSNull { return "" }
    return chatText(v)
}

/// TS 的 !!x
private func chatTruthy(_ v: Any?) -> Bool {
    guard let v = v else { return false }
    if v is NSNull { return false }
    if let b = chatBool(v) { return b }
    if let s = v as? String { return !s.isEmpty }
    if v is NSNumber || v is Int || v is Double {
        let d: Double = chatNum(v)
        return !(d == 0 || d.isNaN)
    }
    return true
}

/// TS 的 slice(0, n)：照 UTF-16 的長度切
private func chatSlice(_ s: String, _ n: Int) -> String {
    let units: [UInt16] = Array(s.utf16.prefix(n))
    return String(decoding: units, as: UTF16.self)
}

private func chatPart(_ v: Any?) -> Part? {
    guard let s = v as? String else { return nil }
    return Part(rawValue: s)
}

/* ---------- 把動作套到行程上 ---------- */

private func chatStop(_ p: Place, _ why: String) -> Stop {
    return Stop(
        id: p.id, n: p.n, kr: p.kr, a: p.a, s: p.s, c: p.c, lat: p.lat, lng: p.lng,
        b: p.b, fee: p.fee, tip: p.tip, l: p.l, up: p.up, f: p.f, ic: p.ic,
        status: .kept, swaps: 0, why: why
    )
}

/// o 是候選清單的代號（字串），或 AI 自己提的地點（物件）。其他的都不收
private func chatMkPlace(_ t: Trip, _ o: Any?) -> Stop? {
    guard let raw = o else { return nil }
    if let id = raw as? String {
        let found: Place? = PLACES.first { (q: Place) -> Bool in q.id == id }
        guard let p = found else { return nil }
        if usedIds(t).contains(p.id) { return nil }
        return chatStop(p, "跟 AI 討論時加的")
    }
    guard let obj = raw as? [String: Any] else { return nil }
    if !chatTruthy(obj["n"]) { return nil }
    let lat: Double = chatNum(obj["lat"])
    let lng: Double = chatNum(obj["lng"])
    let okLL: Bool = lat > 33 && lat < 39 && lng > 124 && lng < 131
    var c: Cat = Cat.sight
    if let word = obj["c"] as? String, let cat = Cat(rawValue: word), CAT[cat] != nil { c = cat }
    let size: StopSize = (obj["s"] as? String) == "L" ? StopSize.L : StopSize.S
    let tip: String = chatSlice(chatTextOrEmpty(obj["tip"]), 80)
    let latOut: Double? = okLL ? lat : nil
    let lngOut: Double? = okLL ? lng : nil
    return Stop(
        id: newId("ai"),
        n: chatSlice(chatText(obj["n"]), 40),
        kr: chatSlice(chatTextOrEmpty(obj["kr"]), 60),
        a: nil,
        s: size,
        c: c,
        lat: latOut,
        lng: lngOut,
        tip: tip.isEmpty ? nil : tip,  // TS 存的是空字串；Swift 這邊空的一律 nil（跟 a 一樣）
        status: .kept,
        swaps: 0,
        why: "AI 提的，還沒核對過",
        ai: true
    )
}

private func chatWhere(_ day: Int, _ part: Part) -> String {
    return "第 \(day) 天\(PART[part] ?? "")"
}

/// 天數或時段不合格時也要講得出「第幾天什麼時段」
private func chatWhereRaw(_ day: Double, _ part: Part?) -> String {
    var word: String = ""
    if let p = part { word = PART[p] ?? "" }
    return "第 \(chatNumText(day)) 天\(word)"
}

/// 做一步。回沒做成的原因，做成了回 nil。不認得的 op 什麼都不做
private func chatApplyOne(_ t: inout Trip, _ seeds: inout [Seed], _ o: [String: Any], _ changes: inout [String]) -> String? {
    guard let op = o["op"] as? String else { return nil }
    var err: String? = nil
    if op == "move" {
        let id: String? = o["id"] as? String
        var x: Found? = nil
        if let id = id { x = findItem(t, id) }
        var from: String = ""
        if let x = x { from = chatWhere(x.s.day, x.s.part) }
        let dayRaw: Double = chatNum(o["day"])
        let part: Part? = chatPart(o["part"])
        if let id = id, x != nil {
            if let day = chatWhole(dayRaw), let part = part {
                err = moveItem(&t, id, day, part)
            } else {
                err = "\(chatWhereRaw(dayRaw, part))你在路上，放不進去"
            }
        } else {
            err = "找不到那一站"
        }
        if err == nil, let x = x, let day = chatWhole(dayRaw), let part = part {
            changes.append("「\(x.it.n)」\(from) → \(chatWhere(day, part))")
        }
    } else if op == "swapParts" {
        let dayRaw: Double = chatNum(o["day"])
        if let day = chatWhole(dayRaw), let a = chatPart(o["a"]), let b = chatPart(o["b"]) {
            err = swapParts(&t, day, a, b)
            if err == nil {
                changes.append("第 \(chatText(o["day"])) 天\(PART[need: a])和\(PART[need: b])對調")
            }
        } else {
            err = "第 \(chatNumText(dayRaw)) 天沒有兩個時段可以對調"
        }
    } else if op == "swapDays" {
        if let a = chatWhole(chatNum(o["a"])), let b = chatWhole(chatNum(o["b"])) {
            err = swapDays(&t, a, b)
            if err == nil {
                changes.append("第 \(chatText(o["a"])) 天和第 \(chatText(o["b"])) 天整天對調")
            }
        } else {
            err = "這兩天沒有對得上的時段"
        }
    } else if op == "remove" {
        var it: Stop? = nil
        if let id = o["id"] as? String {
            it = seedOut(&t, &seeds, id, "用講的改行程時拿掉的")
        }
        if let it = it {
            changes.append("「\(it.n)」→ 下次再來")
        } else {
            err = "找不到要拿掉的那一站"
        }
    } else if op == "add" {
        let dayRaw: Double = chatNum(o["day"])
        let part: Part? = chatPart(o["part"])
        var si: Int? = nil
        if let day = chatWhole(dayRaw), let part = part { si = slotAt(t, day, part) }
        // TS 的 o.id ?? o.place：id 沒給或是 null 才看 place
        var src: Any? = o["id"]
        if src == nil || src is NSNull { src = o["place"] }
        let p: Stop? = chatMkPlace(t, src)
        if let si = si, let day = chatWhole(dayRaw), let part = part {
            if let p = p {
                t.slots[si].items.append(p)
                if part != .eve { t.slots[si].rest = false }
                changes.append("加了「\(p.n)」在\(chatWhere(day, part))")
            } else {
                err = "要加的地方不在候選裡"
            }
        } else {
            err = "\(chatWhereRaw(dayRaw, part))你在路上"
        }
    } else if op == "replace" {
        var x: Found? = nil
        if let id = o["id"] as? String { x = findItem(t, id) }
        let p: Stop? = chatMkPlace(t, o["with"])
        if let x = x, let p = p {
            t.slots[x.si].items[x.ii] = p
            changes.append("「\(x.it.n)」換成「\(p.n)」")
        } else {
            err = "換不了，找不到其中一個"
        }
    } else if op == "rest" {
        let dayRaw: Double = chatNum(o["day"])
        let part: Part? = chatPart(o["part"])
        var si: Int? = nil
        if let day = chatWhole(dayRaw), let part = part { si = slotAt(t, day, part) }
        if let si = si, let day = chatWhole(dayRaw), let part = part {
            let on: Bool = chatTruthy(o["on"])
            t.slots[si].rest = on
            changes.append("\(chatWhere(day, part))\(on ? "改成留白" : "取消留白")")
        } else {
            err = "那個時段你在路上"
        }
    }
    return err
}

/// 把一串動作套到行程上。changes 是給人看的「哪一站從哪到哪」，notes 是沒做成的原因。
/// ops 是 JSONSerialization 解出來的東西（AI 回的，不可信），也可以直接給 [Op]
@discardableResult
func applyOps(_ t: inout Trip, _ seeds: inout [Seed], _ ops: Any?) -> (changes: [String], notes: [String]) {
    var changes: [String] = []
    var notes: [String] = []
    guard let list = ops as? [Any] else { return (changes: changes, notes: notes) }
    for raw in list.prefix(20) {
        // TS 碰到 null 會丟例外，被 catch 接住記成這一句
        if raw is NSNull {
            notes.append("有一步沒做成")
            continue
        }
        var obj: [String: Any]? = nil
        if let typed = raw as? Op {
            obj = opJSON(typed)
        } else {
            obj = raw as? [String: Any]
        }
        // 不是物件的（數字、字串、陣列）在 TS 是每個分支都不成立，什麼都不做
        guard let o = obj else { continue }
        if let err = chatApplyOne(&t, &seeds, o, &changes), !err.isEmpty {
            notes.append(err)
        }
    }
    return (changes: changes, notes: notes)
}

/* ---------- 接 AI 的那條路 ---------- */

/// 後端的網址。TS 是讀環境變數，這裡由 app 啟動時設
var AI_ENDPOINT: String = ""

func aiReady() -> Bool {
    return AI_ENDPOINT.count > 0
}

func aiPrompt(_ msg: String, _ t: Trip, _ base: Settings, _ chat: [ChatMsg]) -> String {
    let st: Settings = tripSettings(base, t.tweaks)
    let tweak: String = tweakSummary(t)
    let used: Set<String> = usedIds(t)
    var candLines: [String] = []
    for p in PLACES {
        if used.contains(p.id) || banned(p, st) { continue }
        let size: String = p.s == .L ? "大" : "小"
        let book: String = p.b == true ? ",要先訂" : ""
        candLines.append("[\(p.id)] \(p.n)(\(size),\(CAT[need: p.c]),\(AREA[need: p.a])\(book))")
    }
    let cand: String = candLines.joined(separator: "\n")
    let talk: [ChatMsg] = chat.filter { (m: ChatMsg) -> Bool in m.r != .sys }
    let recent: [ChatMsg] = Array(talk.suffix(8))
    let histLines: [String] = recent.map { (m: ChatMsg) -> String in
        return (m.r == .me ? "使用者：" : "你：") + m.t
    }
    let hist: String = histLines.joined(separator: "\n")
    let habit: String = settingsSummary(st)
    let people: Int = t.people == 0 ? 1 : t.people
    let tweakLine: String = tweak.isEmpty ? "" : "這趟特別的地方：" + tweak + "。"
    let plan: String = planText(t, true)
    let histBlock: String = hist.isEmpty ? "" : "前面的對話：\n" + hist + "\n\n"

    let head: String = """
你是旅遊行程 app「蘿蔔旅行」裡的助手，幫一位台灣使用者調整他的首爾行程。用繁體中文、口語、簡短回答（三句內），不要用 markdown、不要用表情符號。

規則：
- 一天最多 2 個主要景點（s 是 L 的站）。使用者堅持要超過時照做，但在 reply 裡提醒會累。
- 第一天和最後一天只排順路的小地方（s 是 S 的站）。回覆使用者時說「主要景點」「順路的小地方」，不要說「大站」「小站」。標「在路上」的時段不能排東西。
- 同一個半天的站盡量在同一帶，減少來回跑。
- 你不知道即時資訊。營業時間、票價、是否需要預約都不要講成確定的事，說「去之前查一下」。
- 要加新的地方時，優先從候選清單挑（用它的 id）。清單裡沒有適合的，才自己提一個真實存在的首爾地點，給中文名、韓文名、類別、大小、大概經緯度。
- 使用者只是問問題、沒有要改行程時，ops 給空陣列。
- 使用者的過敏是硬規則：不要加主打那些食材的店或小吃。你不知道每家店的食材，所以只要動到吃的站，reply 裡提醒他點餐前出示過敏告知卡、自己確認。
- 「絕對不吃」的不要排；「不愛吃」的盡量避開，真的排了要在 reply 裡先講。
- 使用者說過「以後都不排」的站或類別，不要加回來。
"""

    var mid: String = "\n\n使用者的習慣：\(habit)。這趟 \(people) 人，\(t.start) 出發。\(tweakLine)"
    mid += "\n\n目前行程（方括號裡是 id）：\n\(plan)\n還沒用到的候選：\n\(cand)"
    mid += "\n\n\(histBlock)使用者現在說：\(msg)\n\n"

    let tail: String = """
只回一個 JSON 物件，不要有其他文字：
{"reply":"給使用者看的話","ops":[...]}
ops 可用的動作：
{"op":"move","id":"p3","day":2,"part":"am"}        把一站移到某天某時段（part: am/pm/eve）
{"op":"swapParts","day":2,"a":"am","b":"pm"}       同一天兩個時段對調
{"op":"swapDays","a":2,"b":4}                      兩天整天對調
{"op":"remove","id":"p3"}                          拿掉（會放進下次再來）
{"op":"add","day":3,"part":"pm","id":"p12"}        從候選加進來
{"op":"add","day":3,"part":"pm","place":{"n":"中文名","kr":"韓文名","c":"eat|shop|fun|sight|art|nature|cafe|night|kpop","s":"L|S","tip":"一句須知","lat":37.5,"lng":127.0}}
{"op":"replace","id":"p3","with":"p12"}            換成候選裡的另一個（with 也可以是上面那種 place 物件）
{"op":"rest","day":3,"part":"pm","on":true}        把某個時段設成留白或取消留白
"""

    return head + mid + tail
}

/// 送去後端時會出的錯。TS 是丟 Error('HTTP 500') 這種
enum AskError: Error, Equatable, CustomStringConvertible {
    case badURL
    case http(Int)
    case badReply

    var description: String {
        switch self {
        case .badURL:
            return "後端網址不對"
        case .http(let status):
            return "HTTP \(status)"
        case .badReply:
            return "後端回的不是看得懂的 JSON"
        }
    }
}

/// 送到自己的後端。後端要回 {reply, ops}，或是 {text: "…含 JSON 的文字…"}
func askRemote(_ prompt: String, _ endpoint: String = AI_ENDPOINT) async throws -> BrainOut {
    guard let url = URL(string: endpoint) else { throw AskError.badURL }
    var req: URLRequest = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let payload: [String: Any] = ["prompt": prompt]
    req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
    let request: URLRequest = req

    // 用 completion handler 包一層：Linux 的 URLSession 不一定有 async 版的 data(for:)
    let got: (body: Data, status: Int?) = try await withCheckedThrowingContinuation {
        (cont: CheckedContinuation<(body: Data, status: Int?), Error>) -> Void in
        let task: URLSessionDataTask = URLSession.shared.dataTask(with: request) {
            (data: Data?, res: URLResponse?, error: Error?) -> Void in
            if let error = error {
                cont.resume(throwing: error)
                return
            }
            let status: Int? = (res as? HTTPURLResponse)?.statusCode
            cont.resume(returning: (body: data ?? Data(), status: status))
        }
        task.resume()
    }

    if let status = got.status, !(status >= 200 && status < 300) {
        throw AskError.http(status)
    }
    let data: Any = try JSONSerialization.jsonObject(with: got.body, options: [.allowFragments])
    // TS 對 null 讀 .text 會丟例外
    if data is NSNull { throw AskError.badReply }
    var parsed: Any = data
    if let obj = data as? [String: Any], let text = obj["text"] as? String {
        // 文字裡第一個 { 到最後一個 } 當成 JSON；找不到就當成空物件
        var json: String = "{}"
        if let m = chatMatch("\\{[\\s\\S]*\\}", text), let whole = chatGroup(m, 0) { json = whole }
        parsed = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.allowFragments])
    }
    let dict: [String: Any] = (parsed as? [String: Any]) ?? [:]
    var reply: String = "好了。"
    if let r = dict["reply"], !(r is NSNull) { reply = chatText(r) }
    let ops: [Any] = (dict["ops"] as? [Any]) ?? []
    return BrainOut(reply: chatSlice(reply, 600), ops: ops)
}

private func chatOpHasAiPlace(_ o: Op) -> Bool {
    switch o {
    case .add(_, _, _, let place):
        return place != nil
    case .replace(_, let with):
        switch with {
        case .id:
            return false
        case .place:
            return true
        }
    case .move, .swapParts, .swapDays, .remove, .rest:
        return false
    }
}

/// 這一串動作裡有沒有 AI 自己提的地點（不是候選清單裡的）
func hasAiPlace(_ ops: [Op]) -> Bool {
    return ops.contains { (o: Op) -> Bool in chatOpHasAiPlace(o) }
}

/// 同上，吃還沒驗過的 JSON（BrainOut.ops）
func hasAiPlace(_ ops: [Any]) -> Bool {
    for raw in ops {
        if let typed = raw as? Op {
            if chatOpHasAiPlace(typed) { return true }
            continue
        }
        guard let o = raw as? [String: Any], let op = o["op"] as? String else { continue }
        if op == "add" && chatTruthy(o["place"]) { return true }
        // TS 是 typeof o.with === 'object'：物件、陣列、null 都算
        if op == "replace", let w = o["with"] {
            if w is NSNull || w is [String: Any] || w is [Any] { return true }
        }
    }
    return false
}
