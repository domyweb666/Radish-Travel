// 蘿蔔人姿勢的測試。照 mobile/tests/buddy.test.ts 搬。
import XCTest
@testable import RadishCore

final class BuddyTests: XCTestCase {
    /// TS 的 nums：姿勢裡所有數值欄位
    private func nums(_ p: Pose) -> [(String, Double)] {
        return [
            ("ry", p.ry), ("lean", p.lean), ("head", p.head), ("hy", p.hy), ("sh", p.sh),
            ("lS", p.lS), ("lE", p.lE), ("rS", p.rS), ("rE", p.rE),
            ("lH", p.lH), ("lK", p.lK), ("rH", p.rH), ("rK", p.rK),
            ("eyeH", p.eyeH), ("lookX", p.lookX), ("lookY", p.lookY), ("brow", p.brow), ("browY", p.browY),
            ("squash", p.squash), ("tl", p.tl), ("hs", p.hs),
            ("happy", p.happy), ("bubble", p.bubble), ("sweat", p.sweat),
            ("t", p.t),
        ]
    }

    func test每個動作在任何時間點算出來的都是正常數字() {
        for a in BUDDY_ACTIONS {
            var t: Double = 0
            while t < 8 {
                let p: Pose = poseAt(a, t, .up)
                for (k, v) in nums(p) {
                    XCTAssertTrue(v.isFinite, "\(a.rawValue) t=\(String(format: "%.2f", t)) \(k)=\(v)")
                }
                let k: Skeleton = skeleton(p)
                var pts: [Pt] = [k.hip, k.neck]
                for leg in k.legs { pts.append(contentsOf: leg) }
                for arm in k.arms { pts.append(contentsOf: arm) }
                for pt in pts {
                    XCTAssertTrue(pt.x.isFinite && pt.y.isFinite, "\(a.rawValue) 的骨架有壞掉的座標")
                }
                t += 0.07
            }
        }
    }

    func test不做成癮機制_沒有大慶祝和打瞌睡() {
        let names: [String] = BUDDY_ACTIONS.map { (a: BuddyAction) -> String in a.rawValue }
        XCTAssertFalse(names.contains("bigcheer"))
        XCTAssertFalse(names.contains("sleep"))
    }

    func test每個動作都有_減少動態效果_用的靜止格() {
        for a in BUDDY_ACTIONS {
            XCTAssertNotNil(STILL_AT[a], "\(a.rawValue) 沒有靜止格")
        }
    }

    func test站著的時候腳踩在地上_歡呼時會離地() {
        let idle: Skeleton = skeleton(poseAt(.idle, 1))
        let ankleY: Double = idle.legs[0][2].y
        XCTAssertTrue(abs(ankleY - 380) < 6, "踝的高度 \(ankleY)")
        XCTAssertEqual(idle.lift, 0)
        XCTAssertTrue(skeleton(poseAt(.cheer, STILL_AT[need: .cheer])).lift > 0.5)
    }

    func test換動作的過渡_頭尾分別等於前後兩個姿勢_中間在兩者之間() {
        let a: Pose = poseAt(.idle, 1)
        let b: Pose = poseAt(.wave, 0.2)
        XCTAssertEqual(blend(a, b, 0).rS, a.rS)
        XCTAssertEqual(blend(a, b, 1).rS, b.rS)
        let mid: Double = blend(a, b, 0.5).rS
        XCTAssertTrue(mid > min(a.rS, b.rS) && mid < max(a.rS, b.rS))
        XCTAssertEqual(blend(poseAt(.idle, 1), poseAt(.think, 1), 0.2).mouth, .smile)
        XCTAssertEqual(blend(poseAt(.idle, 1), poseAt(.think, 1), 0.8).mouth, .flat)
    }
}
