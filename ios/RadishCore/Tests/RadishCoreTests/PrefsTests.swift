// 喜好設定與這趟臨時調整的測試。照 mobile/tests/prefs.test.ts 一個一個搬。
import XCTest

@testable import RadishCore

private func prefsDraft(days: Int = 6, start: String = "2026-12-04", tweaks: [Tweak]? = nil) -> TripDraft {
    return TripDraft(
        tweaks: tweaks, city: nil, base: nil, stayName: nil, name: nil, cover: nil,
        start: start, days: days, arrive: .am, leave: .eve, people: 2
    )
}

private func stopsOf(_ d: TripDraft, _ st: Settings) -> [Stop] {
    let all: [Found] = allItems(generate(d, st))
    return all.map { (x: Found) -> Stop in x.it }
}

final class PrefsTests: XCTestCase {
    func test這趟臨時調整_只改這一趟_存好的偏好原樣() throws {
        var st: Settings = defaultSettings()
        st.pace = .fast
        st.food = [.street: 1, .local: 2, .famous: 3, .fine: 2]
        st.stay = .nice
        st.budget = 2500
        let before: Settings = st
        let eff: Settings = tripSettings(st, [.elder, .save])
        XCTAssertEqual(eff.walk, Walk.less)
        XCTAssertTrue(eff.body.contains(.stairs))
        XCTAssertEqual(eff.pace, Pace.mid)
        XCTAssertEqual(eff.food[.fine], 0)
        XCTAssertEqual(eff.stay, StayKind.cheap)
        _ = generate(prefsDraft(tweaks: [.elder, .save]), st)
        XCTAssertEqual(st, before, "平常的偏好沒被動到")
        XCTAssertEqual(tripSettings(st, nil), st)
    }

    func test帶長輩_不排坡多階梯多的站_站和站之間超過500公尺不用走的() throws {
        let st: Settings = defaultSettings()
        var fast: Settings = st
        fast.pace = .fast
        let usual: [Stop] = stopsOf(prefsDraft(days: 10), fast)
        XCTAssertTrue(usual.contains { (x: Stop) -> Bool in x.up == true }, "平常會排到有坡的站")
        let t: Trip = generate(prefsDraft(days: 10, tweaks: [.elder]), fast)
        let noUp: Bool = allItems(t).allSatisfy { (x: Found) -> Bool in x.it.up != true }
        XCTAssertTrue(noUp)
        for d in stride(from: 1, through: t.days, by: 1) {
            let legs: [Leg?] = dayLegs(t, st, d)
            for one in legs {
                if let l = one, l.mode == "走路" {
                    XCTAssertTrue(l.km <= 0.5)
                }
            }
        }
        XCTAssertEqual(draftOf(t).tweaks, [Tweak.elder], "重排時這趟的調整還在")
    }

    func test想省一點_有要慶祝的事_晚餐和花費跟著變() throws {
        var st: Settings = defaultSettings()
        st.food = [.street: 1, .local: 1, .famous: 1, .fine: 3]
        st.stay = .nice
        st.budget = 4000
        let plain: Trip = generate(prefsDraft(), st)
        let saved: Trip = generate(prefsDraft(tweaks: [.save]), st)
        let plainHasFine: Bool = allItems(plain).contains { (x: Found) -> Bool in x.it.f == FoodKind.fine }
        XCTAssertTrue(plainHasFine)
        let savedNoFine: Bool = allItems(saved).allSatisfy { (x: Found) -> Bool in x.it.f != FoodKind.fine }
        XCTAssertTrue(savedNoFine, "省的那趟不排精緻餐廳")
        XCTAssertTrue(cost(saved, st).total < cost(plain, st).total)
        let treat: Trip = generate(prefsDraft(tweaks: [.treat]), defaultSettings())
        let fine: [Found] = allItems(treat).filter { (x: Found) -> Bool in x.it.f == FoodKind.fine }
        XCTAssertEqual(fine.count, 1, "平常不吃精緻餐廳的人，這趟剛好排一餐")
        let one: Found = try XCTUnwrap(fine.first)
        XCTAssertEqual(one.s.day, 3)
        XCTAssertTrue(one.it.why.contains("慶祝"), one.it.why)
    }

    func test以後都不排_某一類_某一站_某一種吃的_排行程和換一個都跳過() throws {
        var st: Settings = defaultSettings()
        st.play = [.art: 2]
        st.food = [.street: 2, .local: 2, .famous: 2, .fine: 0]
        let t: Trip = generate(prefsDraft(days: 8), st)
        let artFound: Found? = allItems(t).first { (x: Found) -> Bool in x.it.c == .art }
        let art: Stop = try XCTUnwrap(artFound, "最愛博物館的人會排到博物館").it
        let choices: [LearnChoice] = learnChoices(art, st)
        let kinds: [LearnKind] = choices.map { (c: LearnChoice) -> LearnKind in c.kind }
        XCTAssertEqual(kinds, [LearnKind.place, LearnKind.cat])
        guard choices.count == 2 else { return }
        let x: Learned = learn(&st, choices[1], "測試：你拿掉了" + art.n)
        let noArt: Bool = stopsOf(prefsDraft(days: 8), st).allSatisfy { (i: Stop) -> Bool in i.c != .art }
        XCTAssertTrue(noArt)
        var artAsSight: Stop = art
        artAsSight.c = .sight
        let alts: [Place] = alternatives(generate(prefsDraft(), st), st, artAsSight)
        XCTAssertTrue(alts.allSatisfy { (p: Place) -> Bool in p.c != .art })
        XCTAssertTrue(settingsSummary(st).contains("以後都不排"))
        XCTAssertEqual(learnChoices(art, st).count, 1, "記過的那一類不再問")
        let gone: Learned? = unlearn(&st, x.id)
        XCTAssertEqual(gone?.id, x.id)
        let artBack: Bool = stopsOf(prefsDraft(days: 8), st).contains { (i: Stop) -> Bool in i.c == .art }
        XCTAssertTrue(artBack, "拿掉那一條就會再排")

        let first: Stop = try XCTUnwrap(stopsOf(prefsDraft(), st).first)
        _ = learn(&st, LearnChoice(kind: .place, key: first.id, n: first.n), "測試")
        XCTAssertTrue(banned(first, st))
        let noFirst: Bool = stopsOf(prefsDraft(days: 14), st).allSatisfy { (i: Stop) -> Bool in i.id != first.id }
        XCTAssertTrue(noFirst)

        let famousFound: Stop? = stopsOf(prefsDraft(days: 8), st).first { (i: Stop) -> Bool in i.f == FoodKind.famous }
        let famous: Stop = try XCTUnwrap(famousFound)
        let foodFound: LearnChoice? = learnChoices(famous, st).first { (c: LearnChoice) -> Bool in c.kind == .food }
        let food: LearnChoice = try XCTUnwrap(foodFound)
        _ = learn(&st, food, "測試")
        let noFamous: Bool = stopsOf(prefsDraft(days: 8), st).allSatisfy { (i: Stop) -> Bool in i.f != FoodKind.famous }
        XCTAssertTrue(noFamous)
        var only: Settings = defaultSettings()
        only.food = [.street: 0, .local: 2, .famous: 0, .fine: 0]
        let localFound: Stop? = stopsOf(prefsDraft(), only).first { (i: Stop) -> Bool in i.f == FoodKind.local }
        let local: Stop = try XCTUnwrap(localFound)
        let localHasFood: Bool = learnChoices(local, only).contains { (c: LearnChoice) -> Bool in c.kind == .food }
        XCTAssertFalse(localHasFood, "只剩一種還在吃的，不給記成不排")
        var mineFirst: Stop = first
        mineFirst.mine = true
        XCTAssertEqual(learnChoices(mineFirst, defaultSettings()), [], "自己加的站沒有東西可以記")
    }

    func test怕冷_冬天出發少排整段在戶外的站_別的季節不變() throws {
        var st: Settings = defaultSettings()
        st.pace = .fast
        var cold: Settings = st
        cold.body = [.cold]
        func outdoors(_ d: TripDraft, _ s: Settings) -> Int {
            let list: [Stop] = stopsOf(d, s).filter { (i: Stop) -> Bool in i.c == .nature }
            return list.count
        }
        XCTAssertTrue(outdoors(prefsDraft(days: 8), cold) < outdoors(prefsDraft(days: 8), st))
        let spring: TripDraft = prefsDraft(days: 8, start: "2026-04-10")
        XCTAssertEqual(outdoors(spring, cold), outdoors(spring, st))
    }

    func test過敏告知卡_沒選就沒有卡_選了的韓文都在卡上_也會交給AI() throws {
        XCTAssertNil(allergyCard([]))
        let card: AllergyCard = try XCTUnwrap(allergyCard(["花生", "蝦蟹"]))
        XCTAssertTrue(card.kr.contains("땅콩") && card.kr.contains("새우"))
        XCTAssertTrue(card.zh.contains("花生、蝦蟹"))
        var st: Settings = defaultSettings()
        st.allergy = ["花生"]
        st.avoid = ["內臟"]
        st.meh = ["辣"]
        st.walk = .less
        let t: Trip = generate(prefsDraft(tweaks: [.elder]), st)
        let first: Stop = try XCTUnwrap(allItems(t).first).it
        _ = learn(&st, LearnChoice(kind: .cat, key: "kpop", n: "追星"), "測試")
        let prompt: String = aiPrompt("多排一點吃的", t, st, [])
        XCTAssertTrue(prompt.contains("過敏：花生"))
        XCTAssertTrue(prompt.contains("絕對不吃內臟"))
        XCTAssertTrue(prompt.contains("不愛吃辣"))
        XCTAssertTrue(prompt.contains("這趟特別的地方：帶長輩"))
        XCTAssertFalse(prompt.contains("K-pop 周邊店巡禮"), "說過不排的那一類不會出現在候選裡")
        XCTAssertTrue(prompt.contains(first.n))
    }
}
