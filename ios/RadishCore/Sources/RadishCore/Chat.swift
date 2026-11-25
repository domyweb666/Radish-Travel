// 用講的改行程。兩條路：
// 1. 有接 AI → 把提示詞送去 aiRoute 那個地方（電腦 CLI、自己的金鑰、後端），拿回 {reply, ops}
// 2. 沒接 → 本機只聽得懂幾種固定說法
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

let LOCAL_HINTS: [String] = ["這趟想輕鬆一點", "第 2 天上午下午對調", "第 2 天跟第 3 天對調", "第 3 天輕鬆一點", "重排"]

/// 本機指令認得的「這趟」調整：說到這幾個字就是那一種
private let TWEAK_WORDS: [(word: String, tweak: Tweak)] = [
    (word: "長輩", tweak: .elder), (word: "輕鬆", tweak: .easy), (word: "省", tweak: .save), (word: "慶祝", tweak: .treat),
]

/// 要確認的改動，AI 或本機指令回話時講的那一句
let NEED_CONFIRM: String = "這個要你點頭：下面那張卡按「套用」才會改。"
let AI_HINTS: [String] = ["第 2 天上午下午對調", "第 3 天輕鬆一點", "多排一點咖啡廳", "有一天想整天逛街", "雨天備案是什麼"]

/// 旅途中說要整趟重排時回的話
let NO_REGEN_ON_TRIP: String = "旅途中不整趟重排，去過的站會被洗掉。想改今天剩下的，直接說哪一段。"

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

/// 講重排時可以有的客氣話、贅字。長的放前面，先拿掉長的
private let REGEN_FILLERS: [String] = [
    "照現在的設定", "照新的設定", "照新設定", "照這個調整", "照現在的調整", "照新的調整", "照調整", "照設定", "照這個", "照這樣",
    "這整趟", "整趟", "這一趟", "這趟", "整個", "全部", "行程", "一次", "一遍", "一下",
    "麻煩", "幫我", "那就", "我要", "我想要", "我想", "想要", "請", "那", "就", "把", "再", "都", "好", "吧", "啊", "喔", "啦", "要",
]
private let REGEN_CORES: [String] = ["重排", "重新排", "重新排過", "重新安排"]

/// 這句是不是只在叫 app 整趟重排：「重排」「整趟重排一次」「幫我重新排」。
/// 有接 AI 也由手機自己做（AI 沒有這個動作），所以認得嚴：說不要、只講某一天、還帶別的要求的都不算
func talkWantsRegen(_ raw: String) -> Bool {
    var k: String = chatStrip("[\\s，。、！!,.～~「」]+", raw)
    for w in REGEN_FILLERS {
        k = k.replacingOccurrences(of: w, with: "")
    }
    return REGEN_CORES.contains(k)
}

/// 手機照「重排」做的時候回什麼。旅途中、已經有拔起來的站都不重排：去過的站會被洗掉
private func localRegen(_ t: Trip, _ now: TripNow?) -> BrainOut {
    if now != nil { return BrainOut(reply: NO_REGEN_ON_TRIP, ops: []) }
    if tripVisited(t) { return BrainOut(reply: NO_REGEN_VISITED, ops: []) }
    return BrainOut(reply: "好，整趟重排一次。", ops: [], regen: true)
}

/// 本機指令只做一步，先在複本上照著套一次：套不上、套了跟現在一樣，就老實說沒做；
/// 要確認的說要你點頭；真的套得上才講 done 那一句
private func localStep(_ t: Trip, _ op: Op, _ now: TripNow?, _ done: String) -> BrainOut {
    let o: [String: Any] = opJSON(op)
    var copy: Trip = t
    var seeds: [Seed] = []
    let list: [Any] = [o]
    let r: (changes: [String], notes: [String]) = applyOps(&copy, &seeds, list, now, true)
    if r.changes.isEmpty {
        let why: String = r.notes.first ?? "沒有改到東西"
        return BrainOut(reply: "這個沒做成：\(why)。這趟沒有動。", ops: [])
    }
    if copy == t { return BrainOut(reply: "改了會跟現在一樣，所以這趟沒有動。", ops: []) }
    if opLevel(t, o) == OpLevel.confirm { return BrainOut(reply: NEED_CONFIRM, ops: list) }
    return BrainOut(reply: done, ops: list)
}

/// 這趟沒有這一天的話，回要講的那一句
private func localNoDay(_ t: Trip, _ days: [Int]) -> BrainOut? {
    for d in days where d < 1 || d > t.days {
        let word: String = d == Int.max ? "那一天" : "第 \(d) 天"
        return BrainOut(reply: "這個沒做成：這趟只有 \(t.days) 天，沒有\(word)。這趟沒有動。", ops: [])
    }
    return nil
}

/// 兩天整天對調時，是不是每個時段都對得上。有一邊在路上的時段不會動
private func localWholeSwap(_ t: Trip, _ a: Int, _ b: Int) -> Bool {
    for p in PARTS {
        let hasA: Bool = slotAt(t, a, p) != nil
        let hasB: Bool = slotAt(t, b, p) != nil
        if hasA != hasB { return false }
    }
    return true
}

/// 沒接 AI 時的本機指令。聽不懂就老實說聽不懂，套不上就老實說套不上。
/// now 有給（旅途中）時，「輕鬆一點」只挑還沒過、還沒拔的站
func localBrain(_ raw: String, _ t: Trip, _ now: TripNow? = nil) -> BrainOut {
    // 旅途中說的「今天」就是第幾天，下面的說法都認得
    var msg: String = raw
    if let n = now { msg = msg.replacingOccurrences(of: "今天", with: "第 \(n.day) 天") }
    if talkWantsRegen(raw) { return localRegen(t, now) }
    // 「這趟想輕鬆一點」這種講整趟的，是這趟的調整，要確認。講到第幾天的留給下面
    if msg.contains("這趟") && !msg.contains("第") {
        for w in TWEAK_WORDS where msg.contains(w.word) {
            if (t.tweaks ?? []).contains(w.tweak) {
                return BrainOut(reply: "這趟已經有「\(TWEAK_TEXT[need: w.tweak].name)」了，這趟沒有動。", ops: [])
            }
            let op: [String: Any] = ["op": "setTweak", "tweak": w.tweak.rawValue, "on": true]
            return BrainOut(reply: NEED_CONFIRM, ops: [op])
        }
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*第\\s*([0-9]+)\\s*天.*(對調|交換|互換)", msg),
        let d1 = chatGroup(m, 1), let d2 = chatGroup(m, 2)
    {
        let a: Int = chatInt(d1)
        let b: Int = chatInt(d2)
        if let no = localNoDay(t, [a, b]) { return no }
        var done: String = "第 \(a) 天和第 \(b) 天整天對調了。"
        if !localWholeSwap(t, a, b) { done = "第 \(a) 天和第 \(b) 天對調了，在路上的時段沒有動。" }
        return localStep(t, Op.swapDays(a: a, b: b), now, done)
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*(對調|交換|互換)", msg), let d1 = chatGroup(m, 1) {
        let day: Int = chatInt(d1)
        if let no = localNoDay(t, [day]) { return no }
        let op: Op = Op.swapParts(day: day, a: Part.am, b: Part.pm)
        return localStep(t, op, now, "第 \(day) 天的上午和下午對調了。")
    }
    if let m = chatMatch("把?(.+?)(?:移|搬|挪|改|放)到?第\\s*([0-9]+)\\s*天\\s*(上午|下午|晚上)?", msg),
        let name = chatGroup(m, 1), let d2 = chatGroup(m, 2)
    {
        if let x = chatFind(name, t) {
            var part: Part = x.s.part
            if let word = chatGroup(m, 3), let said = PART_WORD[word] { part = said }
            let day: Int = chatInt(d2)
            if let no = localNoDay(t, [day]) { return no }
            let op: Op = Op.move(id: x.it.id, day: day, part: part)
            return localStep(t, op, now, "「\(x.it.n)」移到第 \(day) 天\(PART[need: part])了。")
        }
    }
    if let m = chatMatch("(?:不要|拿掉|刪掉|移除|不去)(.+)", msg), let rest = chatGroup(m, 1) {
        var name: String = rest.replacingOccurrences(of: "了", with: "")
        name = name.replacingOccurrences(of: "吧", with: "")
        name = name.replacingOccurrences(of: "。", with: "")
        if let x = chatFind(name, t) {
            return localStep(t, Op.remove(id: x.it.id), now, "「\(x.it.n)」拿掉了，放進下次再來。")
        }
    }
    if let m = chatMatch("第\\s*([0-9]+)\\s*天.*(輕鬆|少一點|太累|好累|太滿)", msg), let d1 = chatGroup(m, 1) {
        let day: Int = chatInt(d1)
        if let no = localNoDay(t, [day]) { return no }
        let stops: [Found] = dayStops(t, day).filter { (s: Found) -> Bool in
            return s.it.status != .pulled && !slotPast(now, s.s.day, s.s.part)
        }
        let big: Found? = stops.first { (s: Found) -> Bool in s.it.s == .L }
        guard let x = big ?? stops.first else {
            return BrainOut(reply: "第 \(day) 天沒有還能拿掉的站，這趟沒有動。", ops: [])
        }
        return localStep(t, Op.remove(id: x.it.id), now, "第 \(day) 天拿掉「\(x.it.n)」，鬆一點。")
    }
    // 講到重排，但沒有單純叫整趟重排：不要重排、只重排一天、重排時還要多排什麼
    if msg.contains("重排") || msg.contains("重新排") {
        if now != nil { return BrainOut(reply: NO_REGEN_ON_TRIP, ops: []) }
        return BrainOut(reply: "這趟沒有動。手機只會照現在的設定整趟重排，要的話只說「重排」兩個字。", ops: [])
    }
    return BrainOut(reply: LOCAL_LOST, ops: [])
}

/// 本機指令聽不懂時回的話
let LOCAL_LOST: String =
    "這一版還沒接上 AI，我只聽得懂幾種說法：「第 3 天上午下午對調」「第 2 天跟第 4 天對調」「把景福宮移到第 4 天上午」「不要樂天世界」「第 3 天輕鬆一點」「這趟想輕鬆一點」「重排」。"

/* ---------- 開一趟時寫的那句「想怎麼玩」 ---------- */

/// 給 AI 的那一行：這句講的是整趟（平常這一行寫在看哪一天）
let WISH_FOCUS: String =
    "這句是使用者開這趟時寫的「想怎麼玩」，講的是整趟。行程剛由 app 內建的排法照他選的排好，你照這句在上面改；沒講到的不要動，做不到的在 reply 說清楚。"

/// 那句手機自己答得出的話，回答案。寫在「想怎麼玩」的多半是想要什麼，裡面有「附近」「幾站」這些字也不算在問；
/// 真的是問句、而且只問一件事才給手機答：有「想」的、講了好幾件的，手機答了一件，其他的 AI 就收不到
func wishPhone(_ raw: String, _ d: AppState, _ now: TripNow?) -> String? {
    let marks: [String] = ["？", "?", "嗎", "有哪些"]
    let asks: Bool = marks.contains { (w: String) -> Bool in raw.contains(w) }
    if !asks || raw.contains("想") { return nil }
    let ends: CharacterSet = CharacterSet(charactersIn: "？?。！!.～~ \n")
    let msg: String = raw.trimmingCharacters(in: ends)
    if wishMany(msg) || msg.contains("？") || msg.contains("?") { return nil }
    return phoneAnswer(raw, d, 1, nil, now)
}

/// 講了好幾件。頭尾的標點要先拿掉
private func wishMany(_ msg: String) -> Bool {
    let cuts: [String] = ["，", ",", "。", "；", ";", "、", "\n", "還有", "然後"]
    return cuts.contains { (w: String) -> Bool in msg.contains(w) }
}

/// 沒接 AI 時，本機指令做不做得了那句。只有一件事、而且聽得懂才算：
/// 講了好幾件的，做了一件就當作送過，其他的會掉
func wishLocalCan(_ raw: String, _ t: Trip, _ now: TripNow? = nil) -> Bool {
    let ends: CharacterSet = CharacterSet(charactersIn: "。！!.～~ \n")
    let msg: String = raw.trimmingCharacters(in: ends)
    if msg.isEmpty || wishMany(msg) { return false }
    return localBrain(msg, t, now).reply != LOCAL_LOST
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
    } else if op == "setTweak" {
        let on: Bool = permitOn(o["on"])
        let line: String = opLine(t, o)
        err = setTweak(&t, o["tweak"], on)
        if err == nil { changes.append(line) }
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

/* ---------- 旅途中不能動的：過去的時段、拔起來的站 ---------- */

private func chatSlotPulled(_ t: Trip, _ day: Int, _ part: Part) -> Bool {
    return t.slots.contains { (s: Slot) -> Bool in
        return s.day == day && s.part == part && s.items.contains { (it: Stop) -> Bool in it.status == .pulled }
    }
}

/// 這一站能不能動。能動回 nil
private func chatStopFrozen(_ t: Trip, _ id: Any?, _ now: TripNow?) -> String? {
    guard let id = id as? String, let x = findItem(t, id) else { return nil }
    if x.it.status == .pulled { return "「\(x.it.n)」已經拔起來了，不動它" }
    if slotPast(now, x.s.day, x.s.part) { return "「\(x.it.n)」在已經過了的時段，不動它" }
    return nil
}

/// 這個時段能不能排東西進去。能回 nil
private func chatSlotFrozen(_ dayRaw: Any?, _ partRaw: Any?, _ now: TripNow?) -> String? {
    guard let day = chatWhole(chatNum(dayRaw)), let part = chatPart(partRaw) else { return nil }
    if slotPast(now, day, part) { return "\(chatWhere(day, part))已經過了，不能再排" }
    return nil
}

/// 這一步會不會動到不能動的東西。會就回原因，這一步不做。找不到站、時段不對這類錯，留給 chatApplyOne 講
private func chatFrozen(_ t: Trip, _ o: [String: Any], _ now: TripNow?) -> String? {
    guard let op = o["op"] as? String else { return nil }
    if op == "move" {
        return chatStopFrozen(t, o["id"], now) ?? chatSlotFrozen(o["day"], o["part"], now)
    }
    if op == "remove" || op == "replace" {
        return chatStopFrozen(t, o["id"], now)
    }
    if op == "add" || op == "rest" {
        return chatSlotFrozen(o["day"], o["part"], now)
    }
    if op == "swapParts" {
        guard let day = chatWhole(chatNum(o["day"])) else { return nil }
        for raw in [o["a"], o["b"]] {
            guard let part = chatPart(raw) else { continue }
            if slotPast(now, day, part) || chatSlotPulled(t, day, part) {
                return "第 \(day) 天\(PART[need: part])已經過了或有拔起來的站，不能對調"
            }
        }
        return nil
    }
    if op == "swapDays" {
        for raw in [o["a"], o["b"]] {
            guard let day = chatWhole(chatNum(raw)) else { continue }
            if dayFrozen(t, now, day) {
                return "第 \(day) 天有已經過了的時段或拔起來的站，不能整天對調"
            }
        }
        return nil
    }
    return nil
}

/// 一次最多做幾步
let OPS_MAX: Int = 20

/// splitOps 切掉的那幾步只留數目，交給 applyOps 講出來
struct OpsOver {
    let count: Int
}

/// 把一串動作套到行程上。changes 是給人看的「哪一站從哪到哪」，notes 是沒做成的原因。
/// ops 是 JSONSerialization 解出來的東西（AI 回的，不可信），也可以直接給 [Op]
/// now 有給（旅途中）時，過去的時段不動；拔起來的站不管什麼時候都不動
/// 一次最多 OPS_MAX 步。超過的、看不懂的（不是物件、權限表上沒有的 op）不做，在 notes 寫有幾步沒做
/// 權限表（Permit.swift）上沒有的 op 不做；要確認的 op 只有 confirmed 是 true（使用者按了套用）才做
@discardableResult
func applyOps(
    _ t: inout Trip, _ seeds: inout [Seed], _ ops: Any?, _ now: TripNow? = nil, _ confirmed: Bool = false
) -> (changes: [String], notes: [String]) {
    var changes: [String] = []
    var notes: [String] = []
    guard let list = ops as? [Any] else { return (changes: changes, notes: notes) }
    var todo: [Any] = []
    var over: Int = 0
    var unknown: Int = 0
    for raw in list {
        if let more = raw as? OpsOver {
            over += more.count
        } else if todo.count < OPS_MAX {
            todo.append(raw)
        } else {
            over += 1
        }
    }
    for raw in todo {
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
        // 不是物件的（數字、字串、陣列）、權限表上沒有的：什麼都不做，只記有幾步
        guard let o = obj, let level = opLevel(t, o) else {
            unknown += 1
            continue
        }
        if level == .confirm && !confirmed {
            notes.append("\(opLine(t, o))：要你確認才改")
            continue
        }
        if let stop = chatFrozen(t, o, now) {
            notes.append(stop)
            continue
        }
        if let err = chatApplyOne(&t, &seeds, o, &changes), !err.isEmpty {
            notes.append(err)
        }
    }
    if unknown > 0 { notes.append("有 \(unknown) 步看不懂，沒有做") }
    if over > 0 { notes.append("一次最多做 \(OPS_MAX) 步，後面有 \(over) 步沒做") }
    return (changes: changes, notes: notes)
}

/* ---------- 接 AI 的那條路 ---------- */

/// 後端的網址。TS 是讀環境變數，這裡由 app 啟動時設
var AI_ENDPOINT: String = ""

/// 使用者在「平常的我」自己填的 Claude API 金鑰。app 啟動和改設定時從鑰匙圈讀進來，不進存檔、不進備份。
/// 有填就直接問 Anthropic，不經過蘿蔔旅行的後端
var CLAUDE_KEY: String = ""

/// 連到自己電腦的 Claude CLI（ios/tools/claude-bridge 印的 QR code，http://<IP>:<埠>/ask?t=<密碼>）。
/// 開發測試用：有設就最優先，用那台電腦的 Claude 訂閱回答
var BRIDGE_URL: String = ""

/// 直接問 Claude 用的模型
let CLAUDE_MODEL: String = "claude-opus-5-5"
let CLAUDE_URL: String = "https://api.anthropic.com/v1/messages"
let CLAUDE_VERSION: String = "2026-10-21"
/// 被安全檢查擋下來時，由 Anthropic 那邊自動換一個模型再答一次
let CLAUDE_FALLBACK_BETA: String = "server-side-fallback-2026-07-01"

/// 這一刻要走的那條路。url 是整串網址（電腦 CLI 的網址裡有密碼），只在送的時候用，不存
struct AIRoute {
    let kind: AIKind
    let url: String
}

/// 有連電腦的 CLI 就用它，再來是自己填的金鑰，最後才是後端。都沒有是 nil。
/// 要不要同意、算不算句數、真的送出去，全部用這一個判斷
func aiRoute() -> AIRoute? {
    if !BRIDGE_URL.isEmpty { return AIRoute(kind: .bridge, url: BRIDGE_URL) }
    if !CLAUDE_KEY.isEmpty { return AIRoute(kind: .key, url: CLAUDE_URL) }
    if !AI_ENDPOINT.isEmpty { return AIRoute(kind: .server, url: AI_ENDPOINT) }
    return nil
}

/// 網址只留 scheme、主機、埠。讀不出主機就是空字串
func aiOrigin(_ raw: String) -> String {
    guard let u = URL(string: raw), let scheme = u.scheme, let host = u.host, !host.isEmpty else { return "" }
    var out: String = scheme.lowercased() + "://" + host.lowercased()
    if let port = u.port { out += ":\(port)" }
    return out
}

/// 那條路的終點，記同意、比對同意都用它
func aiDestOf(_ route: AIRoute) -> AIDest {
    return AIDest(kind: route.kind, origin: aiOrigin(route.url))
}

/// 現在會送去哪裡。沒接 AI 是 nil
func aiDestNow() -> AIDest? {
    guard let route = aiRoute() else { return nil }
    return aiDestOf(route)
}

func aiReady() -> Bool {
    return aiRoute() != nil
}

/* ---------- 同意把資料送給 AI：照送去的地方記 ---------- */

/// 這個地方同意過了嗎。讀不出位址的不算同意過
func aiAllowed(_ d: AppState, _ dest: AIDest?) -> Bool {
    guard let dest = dest, !dest.origin.isEmpty else { return false }
    return d.aiAgreed.contains(dest)
}

/// 記下同意送去這個地方。讀不出位址的不記
func agreeAI(_ d: inout AppState, _ dest: AIDest) {
    if dest.origin.isEmpty || d.aiAgreed.contains(dest) { return }
    d.aiAgreed.append(dest)
}

/// 收回同意：全部的地方一起收回
func revokeAI(_ d: inout AppState) {
    d.aiAgreed = []
}

/// 貼上備份時用：備份不能替這支手機同意，留這支手機自己的
func keepAgreed(_ next: inout AppState, _ old: AppState) {
    next.aiAgreed = old.aiAgreed
}

/// 按「同意並送出」那一下要做什麼
enum ConsentStep: Equatable, Sendable {
    /// 畫面上寫的就是現在會送去的地方：記下來、送出去
    case send(AIDest)
    /// 等他按的時候地方換了：不送，照新的地方再問一次
    case askAgain(AIDest)
    /// 現在沒接 AI 了：不送
    case gone
}

/// shown 是說明上寫的那個地方，now 是按下去那一刻會送去的地方
func consentStep(_ shown: AIDest, _ now: AIDest?) -> ConsentStep {
    guard let now = now else { return .gone }
    return shown == now ? ConsentStep.send(now) : ConsentStep.askAgain(now)
}

/// 畫面上寫的位址，例：192.168.1.23:8787。讀不出來是空字串
func aiHost(_ dest: AIDest) -> String {
    guard let r = dest.origin.range(of: "://") else { return "" }
    return String(dest.origin[r.upperBound...])
}

/// 清單上的短名字
func aiDestName(_ dest: AIDest) -> String {
    let host: String = aiHost(dest)
    let tail: String = host.isEmpty ? "" : "（\(host)）"
    switch dest.kind {
    case .bridge:
        return "你連的電腦" + tail
    case .key:
        return "Anthropic（你的金鑰）"
    case .server:
        return "蘿蔔旅行的伺服器" + tail
    }
}

/// 送去哪裡，第一次的說明和平常的我都用這一段
func aiWhereText(_ dest: AIDest) -> String {
    let host: String = aiHost(dest)
    let tail: String = host.isEmpty ? "" : "（\(host)）"
    switch dest.kind {
    case .bridge:
        var out: String = "這些會送到你連的那台電腦\(tail)，由電腦上的 Claude CLI 用那台電腦登入的 Claude 帳號拿去問 Claude，不經過蘿蔔旅行的伺服器。"
        out += "手機跟電腦要在同一個 Wi-Fi"
        out += dest.origin.hasPrefix("https://") ? "。" : "，手機到電腦這一段沒有加密。"
        return out
    case .key:
        return "這些會直接送到 Anthropic 的 Claude，用你自己填的 API 金鑰，費用算在你的 Anthropic 帳號，不經過蘿蔔旅行的伺服器。"
    case .server:
        return "這些會先送到蘿蔔旅行的伺服器\(tail)，再交給 Anthropic 的 Claude。"
    }
}

/* ---------- 句數（❓28，2026-11-23 多米說「幫我設定好」，Agent 先定的） ---------- */

/// 一趟可以問 AI 幾句。照 HANDOFF：第一趟 20 句、之後每趟 100 句
let AI_FIRST_TRIP_LIMIT: Int = 20
let AI_NEXT_TRIP_LIMIT: Int = 100

/// 只有走蘿蔔旅行後端的才算句數（那是 app 出的錢）。
/// 自己填 Claude API 金鑰、連自己電腦的 Claude CLI，費用是自己的，不限句數
func aiMetered() -> Bool {
    return aiRoute()?.kind == AIKind.server
}

/// 這趟還剩幾句。nil 是不限。
/// 算法：AI 有回的才算一句（改了、沒改、只是回答都算）；手機答的、本機指令、沒網路沒送、
/// 沒回好、被結束沒收到、Claude 不回答的都不算。
/// 一趟的句數只多不少：復原、整趟重排、照新設定重排、放一邊再切回來、收掉再復原，都不退也不歸零。
/// 每一趟各算各的，用 Trip.id 認，開新的一趟從 0 算
func aiLeft(_ trip: Trip, firstTrip: Bool, metered: Bool) -> Int? {
    if !metered { return nil }
    let limit: Int = firstTrip ? AI_FIRST_TRIP_LIMIT : AI_NEXT_TRIP_LIMIT
    return max(0, limit - (trip.aiUsed ?? 0))
}

/// 還沒有代號的趟補一個代號（剛開的、舊檔裡的），再把每一趟的 aiUsed 和 aiLog 對齊，取多的那個。
/// 開著的和放一邊的都算。每次改完狀態、讀檔、復原之後都叫一次，所以換回舊的那一份行程，句數也不會變少
func syncAIUsed(_ d: inout AppState) {
    // 先全部記進 aiLog，再全部寫回去：同一趟可能有兩份，兩份要一樣
    if var t = d.trip {
        let id: String = aiTripId(&t)
        d.aiLog[id] = max(d.aiLog[id] ?? 0, t.aiUsed ?? 0)
        d.trip = t
    }
    for i in d.shelf.indices {
        var t: Trip = d.shelf[i].trip
        let id: String = aiTripId(&t)
        d.aiLog[id] = max(d.aiLog[id] ?? 0, t.aiUsed ?? 0)
        d.shelf[i].trip = t
    }
    if var t = d.trip {
        aiFill(&t, d.aiLog)
        d.trip = t
    }
    for i in d.shelf.indices {
        var t: Trip = d.shelf[i].trip
        aiFill(&t, d.aiLog)
        d.shelf[i].trip = t
    }
}

private func aiTripId(_ t: inout Trip) -> String {
    if let id = t.id, !id.isEmpty { return id }
    let made: String = newId("k")
    t.id = made
    return made
}

private func aiFill(_ t: inout Trip, _ log: [String: Int]) {
    guard let id = t.id, let n = log[id] else { return }
    if n > (t.aiUsed ?? 0) { t.aiUsed = n }
}

/// AI 回了一句：tripId 那一趟加一。等回覆的時候那一趟放一邊、收掉了也照算，不會算到別趟頭上
func countAI(_ d: inout AppState, _ tripId: String) {
    syncAIUsed(&d)
    d.aiLog[tripId] = (d.aiLog[tripId] ?? 0) + 1
    syncAIUsed(&d)
}

/// 復原時換回之前那一份行程。句數不跟著退：回到的是哪一趟，就用那一趟問過的句數
func restoreTrip(_ d: inout AppState, _ trip: Trip?) {
    // 換掉之前先把現在的句數記下來
    syncAIUsed(&d)
    d.trip = trip
    syncAIUsed(&d)
}

/// 整包換掉（貼上備份）時，備份裡有、手機裡也有的那幾趟，句數取多的。
/// 手機裡沒有的照備份的算；全部清掉之後就沒有紀錄可以對
func carryAILog(_ next: inout AppState, _ old: AppState) {
    var before: AppState = old
    syncAIUsed(&before)
    syncAIUsed(&next)
    var ids: [String] = next.shelf.compactMap { (x: Shelved) -> String? in x.trip.id }
    if let id = next.trip?.id { ids.append(id) }
    for id in ids {
        next.aiLog[id] = max(next.aiLog[id] ?? 0, before.aiLog[id] ?? 0)
    }
    syncAIUsed(&next)
}

/// 走哪條路看 aiRoute。dest 是使用者同意過的那個地方：跟現在會送去的不一樣就不送
func askAI(_ prompt: String, _ dest: AIDest) async throws -> BrainOut {
    // 路和金鑰先抓下來，後面都用這一份，等回覆時改設定也不會換地方
    let key: String = CLAUDE_KEY
    guard let route = aiRoute(), aiDestOf(route) == dest else { throw AskError.destChanged }
    switch route.kind {
    case .bridge:
        do {
            return try await askRemote(prompt, route.url)
        } catch AskError.http(401) {
            throw AskError.bridgeAuth
        }
    case .key:
        return try await askClaude(prompt, key)
    case .server:
        return try await askRemote(prompt, route.url)
    }
}

/// clock 是按下送出那一刻的「現在」。沒給（舊的測試）就不講現在、不標日期。
/// focus 是使用者講這句時在看哪裡（talkFocus 組的一行），沒給就不講
func aiPrompt(
    _ msg: String, _ t: Trip, _ base: Settings, _ chat: [ChatMsg], _ clock: ChatClock? = nil, _ focus: String = ""
) -> String {
    let st: Settings = tripSettings(base, t.tweaks)
    let tweak: String = tweakSummary(t)
    let used: Set<String> = usedIds(t)
    var candLines: [String] = []
    for p in PLACES {
        if used.contains(p.id) || banned(p, st) { continue }
        // 歇業、搬走的不給 AI 挑
        if let f = factOf(p.id), f.gone != nil { continue }
        let size: String = p.s == .L ? "大" : "小"
        let book: String = p.b == true ? ",要先訂" : ""
        let shut: String = closedTag(t, p.id)
        candLines.append("[\(p.id)] \(p.n)(\(size),\(CAT[need: p.c]),\(AREA[need: p.a])\(book)\(shut))")
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
    let now: TripNow? = tripNow(clock)
    let dated: Bool = clock != nil && !t.start.isEmpty
    var fmt: ((Int) -> String)? = nil
    if dated {
        let trip: Trip = t
        fmt = { (d: Int) -> String in tripDayLabel(trip, d) }
    }
    let plan: String = planText(t, true, fmt, now)
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
- 動到標「自己加的」站、或用 setTweak 改這趟的調整，app 會跳一張卡讓他按「套用」才改。這種時候 reply 說要他確認，不要說已經改好。
"""

    var rules: String = ""
    if dated {
        rules += "\n- 每一天後面是日期和星期幾。括號裡有寫休館日的（例如「週二休」「第 2 天不開」），照寫的對星期幾，不要排在不開的那天；使用者堅持就照做，在 reply 講那天休館。沒寫的，說去之前查。"
    }
    if now != nil {
        rules += "\n- 標「已經過了」的時段、標「拔起來了」的站不能動，也不能把東西排進已經過了的時段。"
        rules += "\n- 使用者說累了、下雨、晚了、多出時間，只調今天還沒過的時段，除非他講的是別天。"
        rules += "\n- 他說「下一站」，指今天還沒拔起來的第一站。"
        rules += "\n- 旅途中不要整趟重排。"
    } else {
        rules += "\n- 你沒有整趟重排的動作。使用者想整趟重排，ops 給空陣列，reply 請他只說「重排」兩個字，app 會自己排。"
    }

    let nowText: String = nowLine(t, clock)
    var mid: String = "\n\n使用者的習慣：\(habit)。這趟 \(people) 人，\(t.start) 出發。\(tweakLine)"
    if !nowText.isEmpty { mid += "\n" + nowText }
    if !focus.isEmpty { mid += "\n" + focus }
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
{"op":"setTweak","tweak":"easy","on":true}         這趟加上或拿掉一個調整（tweak: elder 帶長輩／easy 想輕鬆一點／save 想省一點／treat 有要慶祝的事），要使用者確認
"""

    return head + rules + mid + tail
}

/// 送去後端或 Claude 時會出的錯。TS 是丟 Error('HTTP 500') 這種
enum AskError: Error, Equatable, CustomStringConvertible {
    case badURL
    case http(Int)
    /// 回的看不懂：沒有 JSON、沒有 reply、ops 不是一串
    case badReply
    /// 回到一半就被切斷（stop_reason 是 max_tokens）
    case cutOff
    /// 401、403：金鑰不對、被停用，或沒有權限
    case badKey(Int)
    /// 帳戶沒有額度、要先儲值
    case noCredit
    /// 429、500、529：太多人在用或 Anthropic 那邊出狀況，等一下再試
    case busy(Int)
    /// Claude 的安全檢查不回答這一句
    case refused
    /// 電腦上的轉接程式不認這組密碼（重開過會換密碼）
    case bridgeAuth
    /// 送之前發現會送去的地方跟同意的不一樣，沒有送
    case destChanged

    var description: String {
        switch self {
        case .badURL:
            return "後端網址不對"
        case .http(let status):
            return "HTTP \(status)"
        case .badReply:
            return "AI 回的內容看不懂"
        case .cutOff:
            return "AI 的回覆太長，只收到一半"
        case .badKey(let status):
            return "Claude API 金鑰不能用（HTTP \(status)），到平常的我重新填"
        case .noCredit:
            return "這把金鑰的 Anthropic 帳戶沒有額度了"
        case .busy(let status):
            return "Claude 現在太忙（HTTP \(status)），等一下再送一次"
        case .refused:
            return "Claude 不回答這一句"
        case .bridgeAuth:
            return "電腦上的轉接程式重開過了，到平常的我重掃一次 QR code"
        case .destChanged:
            return "送去的地方剛剛換了，所以沒有送出去"
        }
    }
}

/// POST 一份 JSON，拿回內容和狀態碼。
/// 用 completion handler 包一層：Linux 的 URLSession 不一定有 async 版的 data(for:)
private func postJSON(_ url: URL, _ headers: [String: String], _ payload: [String: Any]) async throws -> (body: Data, status: Int?) {
    var req: URLRequest = URLRequest(url: url)
    req.httpMethod = "POST"
    req.timeoutInterval = 180
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    for (k, v) in headers {
        req.setValue(v, forHTTPHeaderField: k)
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
    let request: URLRequest = req
    return try await withCheckedThrowingContinuation {
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
}

/// 一段含 JSON 的文字 → {reply, ops}。第一個 { 到最後一個 } 當成 JSON。
/// 找不到、讀不懂、沒有 reply 就丟錯：不能沒改卻說「好了」。丟錯會走沒回好那條路（線框 A21），不算句數
func brainFromText(_ text: String) throws -> BrainOut {
    guard let m = chatMatch("\\{[\\s\\S]*\\}", text), let json = chatGroup(m, 0),
        let parsed = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: []),
        let dict = parsed as? [String: Any]
    else { throw AskError.badReply }
    return try brainFromDict(dict)
}

/// reply 要是有字的字串；ops 沒給或是 null 當成沒有要改，給了就要是一串
func brainFromDict(_ dict: [String: Any]) throws -> BrainOut {
    guard let raw = dict["reply"] as? String else { throw AskError.badReply }
    let reply: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if reply.isEmpty { throw AskError.badReply }
    var ops: [Any] = []
    if let given = dict["ops"], !(given is NSNull) {
        guard let list = given as? [Any] else { throw AskError.badReply }
        ops = list
    }
    return BrainOut(reply: chatSlice(reply, 600), ops: ops)
}

/// 自己的後端回的那一包：{reply, ops}，或 {text: "…含 JSON 的文字…"}
func brainFromServer(_ body: Data) throws -> BrainOut {
    guard let data = try? JSONSerialization.jsonObject(with: body, options: [.allowFragments]),
        let obj = data as? [String: Any]
    else { throw AskError.badReply }
    if (obj["stop_reason"] as? String) == "max_tokens" { throw AskError.cutOff }
    if let text = obj["text"] as? String { return try brainFromText(text) }
    return try brainFromDict(obj)
}

/// Claude（Messages API）回的那一包。被擋下、回到一半被切斷、沒有文字，都算沒回好
func brainFromClaude(_ body: Data) throws -> BrainOut {
    guard let data = try? JSONSerialization.jsonObject(with: body, options: []),
        let obj = data as? [String: Any]
    else { throw AskError.badReply }
    let stop: String = (obj["stop_reason"] as? String) ?? ""
    if stop == "refusal" { throw AskError.refused }
    if stop == "max_tokens" { throw AskError.cutOff }
    let blocks: [[String: Any]] = (obj["content"] as? [[String: Any]]) ?? []
    var text: String = ""
    for b in blocks where (b["type"] as? String) == "text" {
        text += (b["text"] as? String) ?? ""
    }
    if text.isEmpty { throw AskError.badReply }
    return try brainFromText(text)
}

/// 直接問 Claude 的 HTTP 標頭
private func claudeHeaders(_ key: String, fallback: Bool) -> [String: String] {
    var h: [String: String] = ["x-api-key": key, "anthropic-version": CLAUDE_VERSION]
    if fallback { h["anthropic-beta"] = CLAUDE_FALLBACK_BETA }
    return h
}

/// 狀態碼不是 2xx 時換成看得懂的錯
private func claudeError(_ status: Int, _ body: Data) -> AskError {
    var type: String = ""
    var message: String = ""
    if let obj = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any],
        let err = obj["error"] as? [String: Any]
    {
        type = (err["type"] as? String) ?? ""
        message = (err["message"] as? String) ?? ""
    }
    if status == 401 || status == 403 { return .badKey(status) }
    if status == 402 || type == "billing_error" || message.lowercased().contains("credit balance") { return .noCredit }
    if status == 429 || status == 529 || status >= 500 { return .busy(status) }
    return .http(status)
}

/// 直接問 Claude（Messages API）。提示詞跟送後端的一樣，Claude 回的文字裡有一個 {reply, ops} 的 JSON。
/// 這是聊天用的短回覆，effort 用 low；被安全檢查擋下時讓 Anthropic 自動換模型（fallbacks: default）
func askClaude(_ prompt: String, _ key: String) async throws -> BrainOut {
    guard let url = URL(string: CLAUDE_URL) else { throw AskError.badURL }
    let payload: [String: Any] = [
        "model": CLAUDE_MODEL,
        "max_tokens": 16000,
        "output_config": ["effort": "low"],
        "fallbacks": "default",
        "messages": [["role": "user", "content": prompt]],
    ]
    let got: (body: Data, status: Int?) = try await postJSON(url, claudeHeaders(key, fallback: true), payload)
    let status: Int = got.status ?? 0
    if !(status >= 200 && status < 300) { throw claudeError(status, got.body) }
    return try brainFromClaude(got.body)
}

/// 連電腦的 CLI 時試一次：把網址的 /ask 換成 /ping，拿回那台電腦的名字
func checkBridge(_ askURL: String) async throws -> String {
    guard let ask = URL(string: askURL), var parts = URLComponents(url: ask, resolvingAgainstBaseURL: false),
        parts.path.hasSuffix("/ask")
    else { throw AskError.badURL }
    parts.path = String(parts.path.dropLast(4)) + "/ping"
    guard let ping = parts.url else { throw AskError.badURL }
    var req: URLRequest = URLRequest(url: ping)
    req.timeoutInterval = 8
    let request: URLRequest = req
    let got: (body: Data, status: Int?) = try await withCheckedThrowingContinuation {
        (cont: CheckedContinuation<(body: Data, status: Int?), Error>) -> Void in
        let task: URLSessionDataTask = URLSession.shared.dataTask(with: request) {
            (data: Data?, res: URLResponse?, error: Error?) -> Void in
            if let error = error {
                cont.resume(throwing: error)
                return
            }
            cont.resume(returning: (body: data ?? Data(), status: (res as? HTTPURLResponse)?.statusCode))
        }
        task.resume()
    }
    let status: Int = got.status ?? 0
    if status == 401 { throw AskError.badKey(401) }
    if !(status >= 200 && status < 300) { throw AskError.http(status) }
    let obj: [String: Any] = (try? JSONSerialization.jsonObject(with: got.body, options: []) as? [String: Any]) ?? [:]
    return (obj["name"] as? String) ?? "電腦"
}

/// 掃到或貼上的是不是轉接程式的網址：http(s)://…/ask?t=…
func looksLikeBridge(_ raw: String) -> Bool {
    guard let u = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
        let scheme = u.scheme, scheme == "http" || scheme == "https", u.host != nil, u.path.hasSuffix("/ask")
    else { return false }
    return (u.queryItems ?? []).contains { (q: URLQueryItem) -> Bool in q.name == "t" && !(q.value ?? "").isEmpty }
}

/// 填金鑰時試一次：送一句很短的，看 Anthropic 認不認得這把金鑰。只看狀態碼，不看內容
func checkClaudeKey(_ key: String) async throws {
    guard let url = URL(string: CLAUDE_URL) else { throw AskError.badURL }
    let payload: [String: Any] = [
        "model": CLAUDE_MODEL,
        "max_tokens": 64,
        "output_config": ["effort": "low"],
        "messages": [["role": "user", "content": "回一個字：好"]],
    ]
    let got: (body: Data, status: Int?) = try await postJSON(url, claudeHeaders(key, fallback: false), payload)
    let status: Int = got.status ?? 0
    if !(status >= 200 && status < 300) { throw claudeError(status, got.body) }
}

/// 送到自己的後端。後端要回 {reply, ops}，或是 {text: "…含 JSON 的文字…"}
func askRemote(_ prompt: String, _ endpoint: String = AI_ENDPOINT) async throws -> BrainOut {
    guard let url = URL(string: endpoint) else { throw AskError.badURL }
    let got: (body: Data, status: Int?) = try await postJSON(url, [:], ["prompt": prompt])
    if let status = got.status, !(status >= 200 && status < 300) {
        throw AskError.http(status)
    }
    return try brainFromServer(got.body)
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

/* ---------- 跟 AI 講：在看哪裡、手機先答、改完每一天差多少（SwiftUI 版才有，線框 A1–A3、A14） ---------- */

/// 句子裡有沒有講到第幾天
func talkMentionsDay(_ msg: String) -> Bool {
    return chatMatch("第\\s*[0-9]+\\s*天", msg) != nil
}

/// 這句在問哪一天：句子裡講了第幾天就用那一天；旅途中說「明天」「今天」照今天算；都沒講就是在看的那一天
func talkDay(_ msg: String, _ fallback: Int, _ now: TripNow?) -> Int {
    if let m = chatMatch("第\\s*([0-9]+)\\s*天", msg), let d = chatGroup(m, 1) {
        return chatInt(d)
    }
    if let n = now {
        if msg.contains("明天") { return n.day + 1 }
        if msg.contains("今天") { return n.day }
    }
    return fallback
}

/// 站名去掉括號裡的補充：「明洞的名店韓定食（挑一間）」→「明洞的名店韓定食」
private func talkBare(_ name: String) -> String {
    let bare: String = chatStrip("（.*?）", name)
    return bare.isEmpty ? name : bare
}

/// 給本機指令聽的那句：「這一站」換成站名、「這天」換成第幾天。
/// prefix 為 true（在看某一天）而且句子沒講到哪一天、也不是講整趟（這趟、重排）時，前面補「第 N 天」
func talkLocal(_ msg: String, _ t: Trip, _ day: Int?, _ stopId: String?, _ prefix: Bool) -> String {
    var out: String = msg
    if let id = stopId, let x = findItem(t, id) {
        let name: String = talkBare(x.it.n)
        for w in ["這一站", "這站", "這裡"] {
            out = out.replacingOccurrences(of: w, with: name)
        }
    }
    if let d = day {
        for w in ["這一天", "這天"] {
            out = out.replacingOccurrences(of: w, with: "第 \(d) 天")
        }
        let open: Bool =
            !talkMentionsDay(out) && !out.contains("這趟") && !out.contains("今天") && !out.contains("明天")
            && !talkWantsRegen(out)
        if prefix && open { out = "第 \(d) 天" + out }
    }
    return out
}

/// 給 AI 的那一行：使用者講這句的時候在看哪裡（輸入列左邊的小標）
func talkFocus(_ t: Trip, _ day: Int?, _ stopId: String?) -> String {
    if let id = stopId, let x = findItem(t, id) {
        let part: String = PART[need: x.s.part]
        return "使用者現在在看「\(x.it.n)」[\(x.it.id)] 這一站（第 \(x.s.day) 天\(part)）。他說「這一站」「這裡」就是它。"
    }
    if let d = day, d >= 1, d <= t.days {
        let label: String = t.start.isEmpty ? "" : "（\(tripDayLabel(t, d))）"
        return "使用者現在在看第 \(d) 天\(label)。他說「這天」「這一天」就是這天；句子裡講了第幾天，以句子為準。"
    }
    return ""
}

/// 句子裡有這些字，就是要改這趟，不給手機答
private let TALK_EDIT_WORDS: [String] = [
    "換", "移", "搬", "挪", "拿掉", "不要", "不去", "加", "排", "對調", "交換", "改", "刪", "取消", "留白",
]

/// 手機自己答得出的問題（❓15 暫定：手機答得出的先由手機答，畫面上標「手機算的，沒有問 AI」）。
/// 答不出來、或句子是要改這趟的，回 nil，交給 AI 或本機指令。
/// day 是在看的那一天，stopId 是在看的那一站（在看某一天時是 nil），now 是旅途中的現在
func phoneAnswer(_ raw: String, _ d: AppState, _ day: Int, _ stopId: String?, _ now: TripNow?) -> String? {
    guard let t = d.trip else { return nil }
    let msg: String = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if msg.isEmpty { return nil }
    if TALK_EDIT_WORDS.contains(where: { (w: String) -> Bool in msg.contains(w) }) { return nil }
    if let id = stopId, let x = findItem(t, id), msg.contains("注意") {
        return phoneStopTip(t, x)
    }
    if msg.contains("要先訂") || msg.contains("要預約") {
        return phoneBooking(t, d.checks)
    }
    let asked: Int = talkDay(msg, day, now)
    if msg.contains("幾站") {
        return phoneCount(t, d.settings, asked, msg.contains("剩"), now)
    }
    if msg.contains("接下來去哪") || msg.contains("下一站") {
        return phoneNext(t, d.settings, now)
    }
    if msg.contains("附近") {
        return phoneNearby(t, d.settings, asked)
    }
    if msg.contains("注意") {
        return phoneNotes(t, asked)
    }
    if msg.contains("去了哪") || msg.contains("去過哪") {
        return phoneVisited(t)
    }
    if msg.contains("下次再來") {
        return phoneSeeds(d.seeds)
    }
    return nil
}

/// 這個地方核對過了嗎（看過官方頁或二手資料）
private func talkChecked(_ id: String) -> Bool {
    guard let f = factOf(id) else { return false }
    return f.status != FactStatus.none
}

/// 要先訂這件事核對過了嗎：核對結果裡有寫怎麼訂（要不要先訂看 needsBook）
private func talkBookChecked(_ id: String) -> Bool {
    guard let f = factOf(id), f.book != nil else { return false }
    return f.status != FactStatus.none
}

/// 一站要注意的。核對過的和還沒核對的分開放，分開講
private struct TalkBits {
    var known: [String]
    var plain: [String]
}

private func talkBits(_ t: Trip, _ x: Found) -> TalkBits {
    let it: Stop = x.it
    var out: TalkBits = TalkBits(known: [], plain: [])
    if it.status != .pulled, let why = closedOnTripDay(t.start, x.s.day, it.id, closedByFacts) {
        let line: String = "這天\(closedWord(it.c))：\(why)"
        if talkChecked(it.id) {
            out.known.append(line)
        } else {
            out.plain.append(line)
        }
    }
    if it.status != .pulled {
        // 那天有開、排的時段不開；不擋但要提醒的公告
        var more: [String] = []
        if let why = closedAtTripPart(t.start, x.s.day, x.s.part, it.id, partClosedByFacts) {
            more.append(partShutLine(x.s.part, why))
        }
        if let why = closedOnTripDay(t.start, x.s.day, it.id, cautionByFacts) { more.append(why) }
        if talkChecked(it.id) {
            out.known.append(contentsOf: more)
        } else {
            out.plain.append(contentsOf: more)
        }
    }
    if let tip = tipOf(it) {
        if tip.status == FactStatus.none {
            out.plain.append(tip.text)
        } else {
            out.known.append(tip.text)
        }
        if let extra = tip.extra { out.plain.append(extra) }
    }
    if needsBook(it) {
        if talkBookChecked(it.id) {
            out.known.append("要先訂")
        } else {
            out.plain.append("要先訂")
        }
    }
    return out
}

private func phoneStopTip(_ t: Trip, _ x: Found) -> String {
    let it: Stop = x.it
    let bits: TalkBits = talkBits(t, x)
    let plain: String = bits.plain.joined(separator: "；")
    if bits.known.isEmpty {
        if bits.plain.isEmpty { return "「\(it.n)」沒有寫要注意的。營業時間、票價去之前查一下。" }
        return "「\(it.n)」：\(plain)。這是資料裡寫的，還沒核對過，去之前查一下。"
    }
    let known: String = bits.known.joined(separator: "；")
    let head: String = "「\(it.n)」：\(known)（\(factLabel(factOf(it.id)))）。"
    if bits.plain.isEmpty { return head }
    return head + "還沒核對過的：\(plain)，去之前查一下。"
}

private func phoneBooking(_ t: Trip, _ checks: [String: Bool]) -> String {
    let all: [Stop] = allItems(t).map { (x: Found) -> Stop in x.it }.filter { (it: Stop) -> Bool in
        return needsBook(it) && it.status == .kept
    }
    if all.isEmpty { return phoneNoBooking(t) }
    let left: [Stop] = unbookedOf(t, checks)
    if left.isEmpty { return "要先訂的 \(all.count) 站，你都在「檢查這趟」打勾了。" }
    let names: [String] = left.map { (it: Stop) -> String in
        let label: String = talkBookChecked(it.id) ? "（\(factLabel(factOf(it.id)))）" : ""
        return "「\(it.n)」\(label)"
    }
    let head: String = "還沒打勾的有 \(left.count) 站：\(names.joined(separator: "、"))。訂好了到「檢查這趟」打勾。"
    let unsure: [Stop] = left.filter { (it: Stop) -> Bool in !talkBookChecked(it.id) }
    if unsure.isEmpty { return head }
    if unsure.count == left.count { return head + "要不要先訂是資料裡寫的，還沒核對過。" }
    let rest: [String] = unsure.map { (it: Stop) -> String in "「\(it.n)」" }
    return head + "\(rest.joined(separator: "、"))要不要先訂是資料裡寫的，還沒核對過。"
}

/// 這趟沒有寫要先訂的站：幾站核對過、幾站沒有，照實講
private func phoneNoBooking(_ t: Trip) -> String {
    // 自己加的沒有資料可以核對，不算
    let kept: [Found] = allItems(t).filter { (x: Found) -> Bool in x.it.status == .kept && x.it.mine != true }
    if kept.isEmpty {
        let own: Bool = allItems(t).contains { (x: Found) -> Bool in x.it.status == .kept }
        return own ? "這趟沒有寫要先訂的站。你自己加的要不要訂，手機不知道。" : "這趟沒有寫要先訂的站。"
    }
    let unsure: Int = kept.filter { (x: Found) -> Bool in !talkChecked(x.it.id) }.count
    let head: String = "這趟沒有寫要先訂的站。"
    if unsure == kept.count { return head + "資料還沒核對過，去之前還是查一下。" }
    if unsure == 0 { return head + "每一站都核對過（官方頁或二手資料）。" }
    return head + "有 \(unsure) 站還沒核對過，去之前還是查一下。"
}

private func phoneCount(_ t: Trip, _ base: Settings, _ day: Int, _ left: Bool, _ now: TripNow?) -> String {
    if day < 1 || day > t.days { return "這趟只有 \(t.days) 天。" }
    var stops: [Found] = dayStops(t, day)
    if left {
        stops = stops.filter { (x: Found) -> Bool in
            return x.it.status == .kept && !slotPast(now, x.s.day, x.s.part)
        }
    }
    if stops.isEmpty { return left ? "第 \(day) 天沒有剩下的站了。" : "第 \(day) 天沒有排站。" }
    let st: Settings = tripSettings(base, t.tweaks)
    var legs: [String] = []
    for i in 1..<stops.count {
        let a: Stop = stops[i - 1].it
        let b: Stop = stops[i].it
        if let l = leg(GeoPt(a), GeoPt(b), st) {
            legs.append("\(talkBare(a.n))到\(talkBare(b.n))，\(l.mode) \(l.min) 分鐘（估）")
        } else {
            legs.append("\(talkBare(a.n))到\(talkBare(b.n))距離不明")
        }
    }
    let head: String = "第 \(day) 天\(left ? "還剩" : "有") \(stops.count) 站。"
    if legs.isEmpty { return head }
    return head + legs.joined(separator: "；") + "。"
}

private func phoneNext(_ t: Trip, _ base: Settings, _ now: TripNow?) -> String {
    guard let n = now else { return "現在不是旅途中。出發之後再問，手機會照那天排的告訴你下一站。" }
    let stops: [Found] = dayStops(t, n.day)
    // 一站都沒排（留白、全部不去），沒有東西可以拔，不能說都拔完了
    if stops.isEmpty { return "今天沒有排站。" }
    guard let i = stops.firstIndex(where: { (x: Found) -> Bool in x.it.status == .kept }) else {
        return "今天排的都拔完了。"
    }
    let x: Found = stops[i]
    var out: String = "下一站是「\(x.it.n)」，\(PART[need: x.s.part])・\(areaOf(x.it))。"
    if i > 0 {
        let prev: Stop = stops[i - 1].it
        if let l = leg(GeoPt(prev), GeoPt(x.it), tripSettings(base, t.tweaks)) {
            out += "從「\(talkBare(prev.n))」\(l.mode) \(l.min) 分鐘（估）。"
        }
    }
    return out
}

private func phoneNearby(_ t: Trip, _ base: Settings, _ day: Int) -> String {
    if day < 1 || day > t.days { return "這趟只有 \(t.days) 天。" }
    let names: [String] = nearbyPool(t, day, tripSettings(base, t.tweaks))
    if names.isEmpty { return "第 \(day) 天那一帶，資料裡沒有還能排的小地方了。" }
    let quoted: [String] = names.map { (n: String) -> String in "「\(n)」" }
    let unsure: [String] = names.filter { (n: String) -> Bool in
        let p: Place? = PLACES.first { (q: Place) -> Bool in q.n == n }
        guard let hit = p else { return true }
        return !talkChecked(hit.id)
    }
    let head: String = "第 \(day) 天那一帶還沒排的：\(quoted.joined(separator: "、"))。這是照區域挑的，沒有照距離排"
    if unsure.isEmpty { return head + "。" }
    if unsure.count == names.count { return head + "，資料也還沒核對過。" }
    let rest: [String] = unsure.map { (n: String) -> String in "「\(n)」" }
    return head + "。\(rest.joined(separator: "、"))的資料還沒核對過。"
}

private func phoneNotes(_ t: Trip, _ day: Int) -> String {
    if day < 1 || day > t.days { return "這趟只有 \(t.days) 天。" }
    let label: String = t.start.isEmpty ? "" : "（\(tripDayLabel(t, day))）"
    let stops: [Found] = dayStops(t, day)
    if stops.isEmpty { return "第 \(day) 天\(label)沒有排站。" }
    var known: [String] = []
    var plain: [String] = []
    for x in stops {
        let bits: TalkBits = talkBits(t, x)
        let name: String = "「\(talkBare(x.it.n))」"
        if !bits.known.isEmpty {
            known.append("\(name)\(bits.known.joined(separator: "，"))（\(factLabel(factOf(x.it.id)))）")
        }
        if !bits.plain.isEmpty { plain.append("\(name)\(bits.plain.joined(separator: "，"))") }
    }
    let plainText: String = plain.joined(separator: "；")
    if known.isEmpty {
        if plain.isEmpty { return "第 \(day) 天\(label)的站沒有特別寫要注意的。營業時間、票價去之前查一下。" }
        return "第 \(day) 天\(label)：\(plainText)。這些是資料裡寫的，還沒核對過，營業時間、票價去之前查一下。"
    }
    let head: String = "第 \(day) 天\(label)：\(known.joined(separator: "；"))。"
    if plain.isEmpty { return head }
    return head + "還沒核對過的：\(plainText)，營業時間、票價去之前查一下。"
}

private func phoneVisited(_ t: Trip) -> String {
    let pulled: [String] = allItems(t).filter { (x: Found) -> Bool in x.it.status == .pulled }.map {
        (x: Found) -> String in "「\(talkBare(x.it.n))」"
    }
    if pulled.isEmpty { return "這趟還沒有拔起來的站。" }
    return "這趟拔起來的有 \(pulled.count) 個：\(pulled.joined(separator: "、"))。有去過但沒按到的，點那一站可以補。"
}

private func phoneSeeds(_ seeds: [Seed]) -> String {
    if seeds.isEmpty { return "下次再來還是空的。" }
    let names: [String] = seeds.prefix(8).map { (x: Seed) -> String in "「\(x.n)」" }
    let more: String = seeds.count > 8 ? "等" : ""
    return "下次再來有 \(seeds.count) 個：\(names.joined(separator: "、"))\(more)。在「旅行」的下次再來看得到全部。"
}

/// 這一天路上大約幾分鐘（估），含從住的地方出發和回去，跟這一天下面那行的加法一樣
private func talkMinutes(_ t: Trip, _ base: Settings, _ day: Int) -> Int {
    var total: Int = 0
    for l in dayLegs(t, base, day) {
        if let l = l { total += l.min }
    }
    return total
}

/// 改完之後每一天差多少：「第 3 天：6 站 → 4 站，路上大約 138 → 90 分鐘（估）」。沒變的天不寫，最多寫 3 天
func dayDeltas(_ before: Trip, _ after: Trip, _ base: Settings) -> [String] {
    var out: [String] = []
    let days: Int = max(before.days, after.days)
    if days < 1 { return out }
    for day in 1...days {
        let a: Int = dayStops(before, day).count
        let b: Int = dayStops(after, day).count
        let ma: Int = talkMinutes(before, base, day)
        let mb: Int = talkMinutes(after, base, day)
        if a == b && ma == mb { continue }
        out.append("第 \(day) 天：\(a) 站 → \(b) 站，路上大約 \(ma) → \(mb) 分鐘（估）")
        if out.count >= 3 { break }
    }
    return out
}
