// 排出第一版行程：generate 和它的私有幫手。照 mobile/src/domain/plan.ts 的 generate 逐行搬。
// 查詢、改行程、花費那些在 Plan.swift。
import Foundation

private let FOOD_KINDS: [FoodKind] = [.street, .local, .famous, .fine]

private let PURPOSE_CATS: [Purpose: [Cat]] = [
    .rest: [.nature, .cafe],
    .eat: [.eat],
    .fun: [.fun],
    .see: [.sight, .art],
]

/// 這一站為什麼被排進來：先講使用者自己說過的，沒有才講位置
private func prefWhy(_ p: Place, _ st: Settings) -> String {
    let like: Int = st.play[p.c] ?? 0
    if like == 2 { return "你最愛\(CAT[need: p.c])" }
    if like == 1 { return "你喜歡\(CAT[need: p.c])" }
    if st.walk == .less && p.l == true { return "你說要少走，這一站輕鬆" }
    let hit: Purpose? = st.purposes.first { (purpose: Purpose) -> Bool in
        let cats: [Cat] = PURPOSE_CATS[purpose] ?? []
        return cats.contains(p.c) || (purpose == .rest && p.l == true)
    }
    if let h = hit { return "你旅行想\(PURPOSE[need: h])" }
    let area: String = AREA[need: p.a]
    return p.s == .L ? "\(area)這一帶的主要景點" : "\(area)這一帶順路的小地方"
}

/// 住哪一帶（BaseKey）對到區域（AreaKey）。四個住宿區的字跟區域的字是同一個
private func areaKey(_ b: BaseKey) -> AreaKey {
    switch b {
    case .C: return AreaKey.C
    case .D: return AreaKey.D
    case .G: return AreaKey.G
    case .I: return AreaKey.I
    }
}

/// 第一天：幾點到，決定剩下哪幾個時段
private func arriveParts(_ arrive: Part) -> [Part] {
    switch arrive {
    case .am: return [.pm, .eve]
    case .pm: return [.eve]
    case .eve: return []
    }
}

/// 最後一天：幾點走，決定前面還有哪幾個時段
private func leaveParts(_ leave: Part) -> [Part] {
    switch leave {
    case .am: return []
    case .pm: return [.am]
    case .eve: return [.am, .pm]
    }
}

private struct AreaScore {
    let a: AreaKey
    let v: Double
}

/// closed 是休館判斷、parts 是時段判斷，平常照核對資料；測試會換成假的
func generate(
    _ d: TripDraft, _ base0: Settings, _ shuffle: Bool = false,
    _ rnd: () -> Double = { Double.random(in: 0..<1) },
    closed: @escaping ClosedCheck = closedByFacts, parts partCheck: @escaping PartCheck = partClosedByFacts
) -> Trip {
    // 裡面有好幾個小函式都要用到 rnd，所以先讓它在這個呼叫期間可以被帶著走
    let out: Trip = withoutActuallyEscaping(rnd) { r in
        generateBody(d, base0, shuffle, r, closed, partCheck)
    }
    return out
}

private func generateBody(
    _ d: TripDraft, _ base0: Settings, _ shuffle: Bool, _ rnd: @escaping () -> Double,
    _ closed: @escaping ClosedCheck, _ partCheck: @escaping PartCheck
) -> Trip {
    let st: Settings = tripSettings(base0, d.tweaks)
    let w: [Cat: Int] = planWeights(st)
    let season: Season? = seasonOf(d.start)
    let hotBad: Bool = season == Season.hot && st.body.contains(.heat)
    let coldBad: Bool = season == Season.cold && st.body.contains(.cold)
    let weather: Bool = hotBad || coldBad
    let noUp: Bool = st.body.contains(.stairs)
    // 這趟有要慶祝的事：中間挑一天晚餐排精緻餐廳
    let hasTreat: Bool = d.tweaks?.contains(.treat) == true
    let treatDay: Int = hasTreat ? Int((Double(d.days) / 2).rounded(.up)) : 0
    var used: Set<String> = []
    let pace: Pace = st.pace
    let base: AreaKey = areaKey(d.base ?? st.base)
    let wantRest: Bool = st.purposes.contains(.rest)
    let lv: [FoodKind: Int] = foodLv(st)
    // 同一組（「挑一間」拆成的那幾間）一趟只排一間。只有晚餐、或長行程的白天沒別組可排了，才排同組的另一間
    var usedGroup: Set<String> = []
    var sameGroupOK: Bool = false
    // 現在排到第幾天的哪個時段，休館判斷用
    var today: Int = 1
    var nowPart: Part = .am
    // 這一天白天排了幾站吃的。白天最多一站，加上晚餐一天最多兩站
    var eatToday: Int = 0

    func jit() -> Double {
        return shuffle ? rnd() * 2.5 : 0
    }
    func score(_ p: Place) -> Int {
        var v: Int = w[p.c] ?? 0
        if wantRest && p.l == true { v += 2 }
        if st.walk == .less && p.l == true { v += 2 }
        if weather && outdoor(p) { v -= 3 }
        return v
    }
    func fits(_ p: Place) -> Bool {
        return !banned(p, st) && !(noUp && p.up == true)
    }
    /// 現在排的這一天、這個時段，這個地方不開
    func shut(_ p: Place) -> Bool {
        if closedOnTripDay(d.start, today, p.id, closed) != nil { return true }
        return closedAtTripPart(d.start, today, nowPart, p.id, partCheck) != nil
    }
    /// 這趟排過了，或排過同一組的另一間。同一間不管怎樣都不排第二次
    func taken(_ p: Place) -> Bool {
        if used.contains(p.id) { return true }
        return !sameGroupOK && usedGroup.contains(placeGroup(p.id))
    }
    /// 這一帶這天還有沒有這種大小的地方可以排
    func anyOpen(_ a: AreaKey, _ size: StopSize) -> Bool {
        for p in PLACES where p.a == a && p.s == size {
            if taken(p) || !fits(p) || shut(p) { continue }
            return true
        }
        return false
    }
    /// 從這幾帶裡挑分數最高、還沒用過、那天沒休館的一站。分數一樣就取資料裡排前面的（TS 是穩定排序後拿第一個）
    func take(_ areas: [AreaKey], _ size: StopSize?, _ want: ((Place) -> Bool)?, _ why: (Place) -> String) -> Stop? {
        var best: Place? = nil
        var bestScore: Double = 0
        for p in PLACES {
            if !areas.contains(p.a) { continue }
            if taken(p) { continue }
            if !fits(p) { continue }
            if let sz = size, p.s != sz { continue }
            if let wantFn = want, !wantFn(p) { continue }
            if shut(p) { continue }
            let v: Double = Double(score(p)) + jit()
            if best == nil || v > bestScore {
                best = p
                bestScore = v
            }
        }
        guard let hit = best else { return nil }
        used.insert(hit.id)
        usedGroup.insert(placeGroup(hit.id))
        if hit.c == .eat && nowPart != .eve { eatToday += 1 }
        return planToStop(hit, why(hit))
    }
    func near(_ a: AreaKey) -> [AreaKey] {
        return [a] + (ADJ[a] ?? [])
    }
    let ALL: [AreaKey] = AreaKey.allCases
    func areaScore(_ a: AreaKey) -> Double {
        var sum: Int = 0
        var count: Int = 0
        for p in PLACES where p.a == a && fits(p) {
            sum += score(p)
            count += 1
        }
        let avg: Double = count > 0 ? Double(sum) / Double(count) : 0
        return avg + jit()
    }
    var scored: [AreaScore] = []
    for a in ALL where a != .J {
        scored.append(AreaScore(a: a, v: areaScore(a)))
    }
    let scoredSorted: [AreaScore] = planStableSorted(scored) { (x: AreaScore, y: AreaScore) -> Bool in
        return x.v > y.v
    }
    let order: [AreaKey] = scoredSorted.map { (x: AreaScore) -> AreaKey in x.a }
    var usedArea: Set<AreaKey> = []
    var slots: [Slot] = []
    func nextArea() -> AreaKey {
        let free: AreaKey? = order.first { (x: AreaKey) -> Bool in !usedArea.contains(x) }
        if let a = free {
            usedArea.insert(a)
            return a
        }
        let first: AreaKey = order.first ?? base
        usedArea.removeAll()
        usedArea.insert(first)
        return first
    }
    var full: [Int] = []
    for i in stride(from: 2, to: d.days, by: 1) { full.append(i) }
    var tripDays: Set<Int> = []
    let wSight: Int = w[.sight] ?? 0
    let wFun: Int = w[.fun] ?? 0
    let wNature: Int = w[.nature] ?? 0
    if d.days >= 5 && pace != .slow && (wSight >= 3 || wFun >= 3 || wNature >= 3) {
        var i: Int = min(2, full.count - 1)
        while i >= 0 && i < full.count && tripDays.count < 3 {
            tripDays.insert(full[i])
            i += 4
        }
    }
    func dayOK(_ p: Place) -> Bool {
        if p.c == .night { return false }
        if p.c != .eat { return true }
        if eatToday > 0 { return false }
        guard let f = p.f else { return false }
        return (f == .street || f == .local) && (lv[f] ?? 0) > 0
    }
    func pref(_ p: Place) -> String {
        return prefWhy(p, st)
    }
    // 晚餐照吃的比例分
    var tot: Int = 0
    for k in FOOD_KINDS { tot += lv[k] ?? 0 }
    var cnt: [FoodKind: Int] = [.street: 0, .local: 0, .famous: 0, .fine: 0]
    var eveK: Int = 0
    func nextKind() -> FoodKind {
        eveK += 1
        var best: FoodKind = .local
        var bv: Double = -1e9
        for k in FOOD_KINDS {
            let level: Int = lv[k] ?? 0
            if level == 0 { continue }
            let share: Double = Double(level) / Double(tot)
            let v: Double = share * Double(eveK) - Double(cnt[k] ?? 0)
            if v > bv {
                bv = v
                best = k
            }
        }
        cnt[best] = (cnt[best] ?? 0) + 1
        return best
    }
    func dinnerWhyOf(_ p: Place) -> String {
        guard let f = p.f else { return pref(p) }
        let text: String = "晚餐吃\(FOOD[need: f].name)"
        // 每一種都說不要的時候會拿小館來排，那不是使用者說的，不講
        switch base0.food[f] ?? 0 {
        case 3: return text + "，你說主要吃這種"
        case 2: return text + "，你說常常吃這種"
        case 1: return text + "，你說偶爾吃這種"
        default: return text
        }
    }
    /// 排到同一組的另一間
    func sameGroupWhy(_ p: Place) -> String {
        guard let f = p.f else { return pref(p) }
        return "晚餐吃\(FOOD[need: f].name)，這一晚沒有別類的店可以排"
    }
    func eatsNow(_ p: Place) -> Bool {
        guard let f = p.f else { return false }
        return p.c == .eat && (lv[f] ?? 0) > 0
    }

    for day in stride(from: 1, through: d.days, by: 1) {
        today = day
        nowPart = .am
        eatToday = 0
        var parts: [Part] = [.am, .pm, .eve]
        if day == 1 { parts = arriveParts(d.arrive) }
        if day == d.days { parts = leaveParts(d.leave) }
        if d.days == 1 {
            let okParts: [Part] = arriveParts(d.arrive)
            parts = parts.filter { (p: Part) -> Bool in okParts.contains(p) }
        }
        let edge: Bool = day == 1 || day == d.days
        let fi: Int = full.firstIndex(of: day) ?? -1
        let lightDay: Bool = !edge && (pace == .fast ? fi % 6 == 5 : fi % 3 == 2)
        var amA: AreaKey = base
        var pmA: AreaKey = base
        if edge {
            amA = base
            pmA = base
        } else if tripDays.contains(day) && anyOpen(AreaKey.J, StopSize.L) {
            // 近郊那天沒有能去的，就照平常的一天排，不要整個白天空著
            amA = AreaKey.J
            pmA = AreaKey.J
        } else {
            amA = nextArea()
            pmA = amA
            if pace != .slow {
                let adj: [AreaKey] = ADJ[amA] ?? []
                let free: [AreaKey] = adj.filter { (x: AreaKey) -> Bool in !usedArea.contains(x) }
                let freeSorted: [AreaKey] = planStableSorted(free) { (x: AreaKey, y: AreaKey) -> Bool in
                    let ix: Int = order.firstIndex(of: x) ?? -1
                    let iy: Int = order.firstIndex(of: y) ?? -1
                    return ix < iy
                }
                pmA = freeSorted.first ?? amA
                usedArea.insert(pmA)
            }
        }
        let edgeWhy: (Place) -> String = { (_: Place) -> String in
            return day == 1 ? "第一天剛到，排輕鬆的" : "最後一天要走，排輕鬆的"
        }
        for part in PARTS {
            if !parts.contains(part) {
                slots.append(Slot(day: day, part: part, off: true, rest: false, items: []))
                continue
            }
            nowPart = part
            let a: AreaKey = part == .am ? amA : pmA
            var items: [Stop] = []
            var restFlag: Bool = false
            let city: [AreaKey] = a == AreaKey.J ? [base] : near(a)
            if part == .eve {
                let treat: Bool = day == treatDay
                var k: FoodKind = FoodKind.fine
                if !treat { k = nextKind() }
                let kind: FoodKind = k
                let dinnerWhy: (Place) -> String
                if treat {
                    dinnerWhy = { (_: Place) -> String in "這趟有要慶祝的事，這一餐排好一點" }
                } else {
                    dinnerWhy = { (p: Place) -> String in dinnerWhyOf(p) }
                }
                let isKind: (Place) -> Bool = { (p: Place) -> Bool in
                    return p.c == .eat && p.f == kind
                }
                var dinner: Stop? = take(city, StopSize.S, isKind, dinnerWhy)
                if dinner == nil { dinner = take(ALL, StopSize.S, isKind, dinnerWhy) }
                if dinner == nil { dinner = take(city, StopSize.S, eatsNow, dinnerWhy) }
                if dinner == nil { dinner = take(ALL, StopSize.S, eatsNow, dinnerWhy) }
                if dinner == nil {
                    // 還開著的每一組都排過了：排同一組沒去過的另一間，不要讓晚餐空著
                    sameGroupOK = true
                    dinner = take(city, StopSize.S, eatsNow, sameGroupWhy)
                    if dinner == nil { dinner = take(ALL, StopSize.S, eatsNow, sameGroupWhy) }
                    sameGroupOK = false
                }
                if let x = dinner { items.append(x) }
                if pace == .fast && !edge {
                    let notEatNotEasy: (Place) -> Bool = { (p: Place) -> Bool in
                        return p.c != .eat && p.l != true
                    }
                    let fastWhy: (Place) -> String = { (_: Place) -> String in "節奏選「趕」，晚上多排一站" }
                    let extra: Stop? = take(city, StopSize.S, notEatNotEasy, fastWhy)
                    if let x = extra { items.append(x) }
                }
                if pace != .slow { restFlag = true }
            } else if edge {
                let easyOK: (Place) -> Bool = { (p: Place) -> Bool in
                    return dayOK(p) && (p.l == true || p.c == .shop || p.c == .cafe || p.c == .eat)
                }
                let noBookOK: (Place) -> Bool = { (p: Place) -> Bool in
                    return dayOK(p) && p.b != true
                }
                var pick: Stop? = take(near(a), StopSize.S, easyOK, edgeWhy)
                if pick == nil { pick = take(near(a), StopSize.S, noBookOK, edgeWhy) }
                if let x = pick { items.append(x) }
            } else if a == AreaKey.J {
                if part == .am {
                    let farWhy: (Place) -> String = { (p: Place) -> String in
                        return "\(pref(p))；近郊來回要一整個白天，排在行程中段"
                    }
                    let far: Stop? = take([AreaKey.J], StopSize.L, nil, farWhy)
                    if let x = far { items.append(x) }
                } else {
                    restFlag = true
                }
            } else {
                var bigTime: Bool = false
                if part == .am {
                    bigTime = st.wake != .late
                } else {
                    bigTime = pace != .slow || st.wake == .late
                }
                let big: Bool = !lightDay && bigTime
                var pick: Stop? = nil
                if big { pick = take([a], StopSize.L, nil, pref) }
                if pick == nil { pick = take([a], StopSize.S, dayOK, pref) }
                if pick == nil { pick = take(near(a), StopSize.S, dayOK, pref) }
                if let x = pick { items.append(x) }
                // 要少走的話，半天只排一站（選「排滿」的例外）
                let first: Stop? = items.first
                var firstSmallOrNone: Bool = true
                if let f = first { firstSmallOrNone = f.s == .S }
                let lessAndHas: Bool = st.walk == .less && first != nil
                if pace == .fast || (firstSmallOrNone && pace != .slow && !lessAndHas) {
                    let sameArea: (Place) -> String = { (_: Place) -> String in
                        if let f = first { return "跟「\(f.n)」同一帶，順路" }
                        return "這一帶順路的小地方"
                    }
                    var more: Stop? = take([a], StopSize.S, dayOK, sameArea)
                    if more == nil { more = take(near(a), StopSize.S, dayOK, sameArea) }
                    if let x = more { items.append(x) }
                }
                if pace == .slow && part == .pm { restFlag = true }
            }
            // 超過七天的行程，白天照上面的規矩一站都挑不到：排同一組沒去過的另一間。吃的留給晚餐
            if d.days > 7 && part != .eve && a != AreaKey.J && items.isEmpty {
                let notEat: (Place) -> Bool = { (p: Place) -> Bool in
                    return p.c != .eat && dayOK(p)
                }
                var fill: Stop? = nil
                sameGroupOK = true
                if edge {
                    let easy: (Place) -> Bool = { (p: Place) -> Bool in
                        return notEat(p) && (p.l == true || p.c == .shop || p.c == .cafe)
                    }
                    let noBook: (Place) -> Bool = { (p: Place) -> Bool in
                        return notEat(p) && p.b != true
                    }
                    fill = take(near(a), StopSize.S, easy, edgeWhy)
                    if fill == nil { fill = take(near(a), StopSize.S, noBook, edgeWhy) }
                } else {
                    fill = take([a], StopSize.S, notEat, pref)
                    if fill == nil { fill = take(near(a), StopSize.S, notEat, pref) }
                }
                sameGroupOK = false
                if let x = fill { items.append(x) }
            }
            if items.isEmpty { restFlag = true }
            slots.append(Slot(day: day, part: part, off: nil, rest: restFlag, items: items))
        }
    }
    return Trip(
        tweaks: d.tweaks, city: d.city, base: d.base, stayName: d.stayName, name: d.name, cover: d.cover,
        start: d.start, days: d.days, arrive: d.arrive, leave: d.leave, people: d.people,
        slots: slots, flight: 0, spend: nil, rate: nil
    )
}
