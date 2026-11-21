// 蘿蔔人的姿勢。身體是八個關節角度，每個動作是角度隨時間變化的一組數值。
// 純計算，不碰畫面，BuddyTests.swift 會驗。照 mobile/src/components/buddy/poses.ts 搬。
// 角度：0 是垂直向下，正值往畫面右邊轉。手肘和膝蓋是相對於上一節的角度。
//
// 不做的動作：大慶祝（連續天數里程碑）、打瞌睡（催人回來）。這兩個違反「不做成癮機制」。
import Foundation

enum BuddyAction: String, Codable, CaseIterable, Sendable {
    case idle, wave, point, think, cheer, shrug, oops, bow
}

enum PointDir: String, Codable, CaseIterable, Sendable {
    case up, right, down, left
}

enum Mouth: String, Codable, CaseIterable, Sendable {
    case smile, open, wavy, o, flat
}

struct Pose: Hashable, Sendable {
    var ry: Double
    var lean: Double
    var head: Double
    var hy: Double
    var sh: Double
    var lS: Double
    var lE: Double
    var rS: Double
    var rE: Double
    var lH: Double
    var lK: Double
    var rH: Double
    var rK: Double
    var eyeH: Double
    var lookX: Double
    var lookY: Double
    var brow: Double
    var browY: Double
    var squash: Double
    var tl: Double
    var hs: Double
    var happy: Double
    var bubble: Double
    var sweat: Double
    var mouth: Mouth
    var t: Double
}

struct Rig: Sendable {
    let hipX: Double = 160
    let hipY: Double = 260
    let ground: Double = 380
    let thigh: Double = 62
    let shin: Double = 62
    let torso: Double = 78
    let shoulderDrop: Double = 12
    let shoulderHalf: Double = 6
    let upper: Double = 44
    let fore: Double = 44
}

let RIG: Rig = Rig()

func basePose() -> Pose {
    return Pose(
        ry: 0, lean: 0, head: 0, hy: 0, sh: 0,
        lS: -38, lE: 143, rS: 38, rE: -143,
        lH: -14, lK: 0, rH: 14, rK: 0,
        eyeH: 12, lookX: 0, lookY: 0, brow: 2, browY: 0,
        squash: 0, tl: 1, hs: 1,
        happy: 0, bubble: 0, sweat: 0,
        mouth: .smile,
        t: 0
    )
}

/// TS 的 ss：平滑階梯
private func buddySS(_ a: Double, _ b: Double, _ x: Double) -> Double {
    let k: Double = max(0, min(1, (x - a) / (b - a)))
    return k * k * (3 - 2 * k)
}

/// TS 的 %（餘數跟著被除數的正負號）
private func buddyMod(_ x: Double, _ m: Double) -> Double {
    return x.truncatingRemainder(dividingBy: m)
}

/// TS 的 ANIMS[action](t, d)：回傳的是「蓋在 basePose() 上之後」的整個姿勢（t 還沒填）
private func buddyAnim(_ action: BuddyAction, _ t: Double, _ d: PointDir) -> Pose {
    var p: Pose = basePose()
    switch action {
    // 站著也要看得出是活的：小尺寸下只有呼吸會看不到，所以身體會晃、眼睛會看、每五秒左右踮一下
    case .idle:
        let b: Double = sin(t * 2.2)
        let c: Double = buddyMod(t, 4.8)
        let h: Double = c < 0.5 ? sin((Double.pi * c) / 0.5) : 0
        p.sh = -2.5 * b
        p.hy = -2 * b
        p.lean = 3 * sin(t * 1.1)
        p.head = 5 * sin(t * 0.9)
        p.lS = -38 - 5 * b
        p.lE = 143 + 8 * b
        p.rS = 38 + 5 * b
        p.rE = -143 - 8 * b
        p.lookX = 3 * sin(t * 0.7)
        p.eyeH = buddyMod(t, 3.6) > 3.46 ? 1.5 : 12
        p.ry = -12 * h
        p.lH = -14 - 5 * h
        p.lK = 14 * h
        p.rH = 14 + 5 * h
        p.rK = -14 * h
    case .wave:
        p.rS = 110
        p.rE = 40 + 22 * sin(t * 9)
        p.lS = -16
        p.lE = -6
        p.head = 5 + 2 * sin(t * 4.5)
        p.lean = 2
        p.brow = 5
        p.browY = -1
        p.hy = -1 * sin(t * 4.5)
    case .point:
        let k: Double = sin(t * 5)
        switch d {
        case .right:
            p.brow = 4
            p.rS = 92
            p.rE = 0
            p.lS = -40
            p.lE = 100
            p.lean = 3 + 1.5 * k
            p.head = 3
            p.lookX = 3
        case .left:
            p.brow = 4
            p.lS = -92
            p.lE = 0
            p.rS = 40
            p.rE = -100
            p.lean = -3 - 1.5 * k
            p.head = -3
            p.lookX = -3
        case .up:
            p.brow = 4
            p.rS = 105
            p.rE = 62
            p.lS = -40
            p.lE = 100
            p.hy = -1.5 * k
            p.sh = -1.5 * k
            p.head = -4
            p.lookY = -3
            p.lookX = 1
        case .down:
            p.brow = 4
            p.rS = 30
            p.rE = 8
            p.lS = -40
            p.lE = 100
            p.lean = 2
            p.head = 9 + 1.5 * k
            p.lookY = 3.5
            p.lookX = 2
        }
    case .think:
        p.rS = 42
        p.rE = 165
        p.lS = -30
        p.lE = 120
        p.head = -8 + 1.5 * sin(t * 1.6)
        p.lean = -1.5
        p.lookX = -2
        p.lookY = -3
        p.brow = 3
        p.browY = -2
        p.bubble = 1
        p.mouth = .flat
    case .cheer:
        let P: Double = 0.72
        let q: Double = buddyMod(t, P) / P
        let h: Double = q < 0.8 ? sin((Double.pi * q) / 0.8) : 0
        let s: Double = q >= 0.8 ? sin((Double.pi * (q - 0.8)) / 0.2) : 0
        let w: Double = sin(t * 15)
        p.ry = -34 * h
        p.squash = 0.07 * s
        p.lS = -105
        p.lE = -62 - 8 * w
        p.rS = 105
        p.rE = 62 + 8 * w
        p.lH = -14 - 12 * h
        p.lK = 34 * h
        p.rH = 14 + 12 * h
        p.rK = -34 * h
        p.brow = -4
        p.browY = -3
        p.happy = 1
        p.mouth = .open
        p.head = 0.9 * w
    case .shrug:
        let c: Double = buddyMod(t, 2.4)
        let u: Double = buddySS(0, 0.3, c) * (1 - buddySS(1.5, 1.9, c))
        p.sh = -6 * u
        p.lS = -16 - 14 * u
        p.lE = -6 - 82 * u
        p.rS = 16 + 14 * u
        p.rE = 6 + 82 * u
        p.head = 8 * u
        p.brow = 2 - 12 * u
        p.browY = -3 * u
        p.mouth = u > 0.4 ? .wavy : .smile
        p.lookY = -1 * u
    case .oops:
        p.rS = 112
        p.rE = 45 + 7 * sin(t * 12)
        p.lS = -16
        p.lE = -6
        p.head = 9
        p.lean = 2
        p.brow = -12
        p.browY = -1
        p.lookY = 3
        p.lookX = -1
        p.mouth = .wavy
        p.sweat = 1
    case .bow:
        let c: Double = buddyMod(t, 2.6)
        let u: Double = buddySS(0, 0.45, c) * (1 - buddySS(1.5, 2.0, c))
        p.lS = -12
        p.lE = -4
        p.rS = 12
        p.rE = 4
        p.tl = 1 - 0.3 * u
        p.hs = 1 - 0.14 * u
        p.hy = 8 * u
        p.lookY = 6 * u
        p.eyeH = 12 - 10.5 * buddySS(0.4, 0.8, u)
        p.brow = 2
        p.browY = 2 * u
    }
    return p
}

let BUDDY_ACTIONS: [BuddyAction] = [.idle, .wave, .point, .think, .cheer, .shrug, .oops, .bow]

/// 「減少動態效果」開著時不播動畫，停在每個動作最好認的那一格
let STILL_AT: [BuddyAction: Double] = [
    .idle: 1, .wave: 0.2, .point: 0.3, .think: 0.5, .cheer: 0.29, .shrug: 0.9, .oops: 0.1, .bow: 1,
]

func poseAt(_ action: BuddyAction, _ t: Double, _ dir: PointDir = .right) -> Pose {
    var p: Pose = buddyAnim(action, t, dir)
    p.t = t
    return p
}

/// 換動作時的過渡：數值內插，嘴型這種非數值的在一半時切換
func blend(_ a: Pose, _ b: Pose, _ k: Double) -> Pose {
    var o: Pose = b
    o.ry = a.ry + (b.ry - a.ry) * k
    o.lean = a.lean + (b.lean - a.lean) * k
    o.head = a.head + (b.head - a.head) * k
    o.hy = a.hy + (b.hy - a.hy) * k
    o.sh = a.sh + (b.sh - a.sh) * k
    o.lS = a.lS + (b.lS - a.lS) * k
    o.lE = a.lE + (b.lE - a.lE) * k
    o.rS = a.rS + (b.rS - a.rS) * k
    o.rE = a.rE + (b.rE - a.rE) * k
    o.lH = a.lH + (b.lH - a.lH) * k
    o.lK = a.lK + (b.lK - a.lK) * k
    o.rH = a.rH + (b.rH - a.rH) * k
    o.rK = a.rK + (b.rK - a.rK) * k
    o.eyeH = a.eyeH + (b.eyeH - a.eyeH) * k
    o.lookX = a.lookX + (b.lookX - a.lookX) * k
    o.lookY = a.lookY + (b.lookY - a.lookY) * k
    o.brow = a.brow + (b.brow - a.brow) * k
    o.browY = a.browY + (b.browY - a.browY) * k
    o.squash = a.squash + (b.squash - a.squash) * k
    o.tl = a.tl + (b.tl - a.tl) * k
    o.hs = a.hs + (b.hs - a.hs) * k
    o.happy = a.happy + (b.happy - a.happy) * k
    o.bubble = a.bubble + (b.bubble - a.bubble) * k
    o.sweat = a.sweat + (b.sweat - a.sweat) * k
    o.mouth = k < 0.5 ? a.mouth : b.mouth
    o.t = b.t
    return o
}

/// TS 的 Pt = [number, number]
struct Pt: Hashable, Sendable {
    var x: Double
    var y: Double
}

private func buddyDirv(_ deg: Double) -> Pt {
    let r: Double = (deg * Double.pi) / 180
    return Pt(x: sin(r), y: cos(r))
}

private func buddyAdd(_ p: Pt, _ v: Pt, _ l: Double) -> Pt {
    return Pt(x: p.x + v.x * l, y: p.y + v.y * l)
}

/// 頭的位置與轉角
struct SkeletonHead: Hashable, Sendable {
    var x: Double
    var y: Double
    var rot: Double
    var scaleY: Double
}

struct Skeleton: Hashable, Sendable {
    var hip: Pt
    var neck: Pt
    /// 腳：髖 → 膝 → 踝 → 腳尖。兩隻（左、右），每隻四個點
    var legs: [[Pt]]
    /// 手：肩 → 肘 → 手。兩隻（左、右），每隻三個點
    var arms: [[Pt]]
    /// 頭的位置與轉角
    var head: SkeletonHead
    /// 離地的程度，0 是站著。影子用
    var lift: Double
}

func skeleton(_ p: Pose) -> Skeleton {
    let R: Rig = RIG
    let hip: Pt = Pt(x: R.hipX, y: R.hipY + p.ry)
    let up: Pt = buddyDirv(180 - p.lean)
    let len: Double = R.torso * p.tl
    let top: Pt = buddyAdd(hip, up, len)
    var sho: Pt = buddyAdd(hip, up, len - R.shoulderDrop)
    sho.y += p.sh

    let legSpecs: [(h: Double, k: Double, side: Double)] = [
        (h: p.lH, k: p.lK, side: -1),
        (h: p.rH, k: p.rK, side: 1),
    ]
    var legs: [[Pt]] = []
    for spec in legSpecs {
        let knee: Pt = buddyAdd(hip, buddyDirv(spec.h), R.thigh)
        let ankle: Pt = buddyAdd(knee, buddyDirv(spec.h + spec.k), R.shin)
        let toe: Pt = Pt(x: ankle.x + spec.side * 12, y: ankle.y + 1)
        legs.append([hip, knee, ankle, toe])
    }

    let armSpecs: [(s: Double, e: Double, side: Double)] = [
        (s: p.lS, e: p.lE, side: -1),
        (s: p.rS, e: p.rE, side: 1),
    ]
    var arms: [[Pt]] = []
    for spec in armSpecs {
        let so: Pt = Pt(x: sho.x + spec.side * R.shoulderHalf, y: sho.y)
        let elbow: Pt = buddyAdd(so, buddyDirv(spec.s), R.upper)
        let hand: Pt = buddyAdd(elbow, buddyDirv(spec.s + spec.e), R.fore)
        arms.append([so, elbow, hand])
    }

    return Skeleton(
        hip: hip,
        neck: Pt(x: top.x, y: top.y + p.sh * 0.5),
        legs: legs,
        arms: arms,
        head: SkeletonHead(x: top.x, y: top.y + p.hy + p.sh * 0.5, rot: p.head + p.lean, scaleY: p.hs),
        lift: max(0, -p.ry / 40)
    )
}
