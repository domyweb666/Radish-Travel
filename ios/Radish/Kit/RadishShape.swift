// 蘿蔔。它是角色，顏色用 Theme.swift 的角色色。
// 現在是占位的向量圖，之後換成黏土插圖。照 mobile/src/components/Radish.tsx 搬。
// 這個檔另外放了 svgPath：把 SVG 的 path 字串變成 SwiftUI 的 Path，蘿蔔人和地點種類圖示也用它。
import SwiftUI

// MARK: - SVG path 字串 → Path

/// 一個字一個字讀 SVG path 字串
private struct SvgScanner {
    let s: [UInt8]
    var i: Int = 0

    init(_ d: String) {
        self.s = Array(d.utf8)
    }

    private static func isSep(_ c: UInt8) -> Bool {
        // 空白、tab、換行、逗號
        return c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C || c == 0x2C
    }

    private static func isDigit(_ c: UInt8) -> Bool {
        return c >= 0x30 && c <= 0x39
    }

    private static func isLetter(_ c: UInt8) -> Bool {
        return (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A)
    }

    mutating func skipSep() {
        while i < s.count && SvgScanner.isSep(s[i]) {
            i += 1
        }
    }

    var atEnd: Bool {
        return i >= s.count
    }

    /// 下一個是指令字母就吃掉並回傳，不是就回 nil（位置不動）
    mutating func command() -> UInt8? {
        skipSep()
        guard i < s.count else { return nil }
        let c: UInt8 = s[i]
        if SvgScanner.isLetter(c) {
            i += 1
            return c
        }
        return nil
    }

    /// 讀一個數字：可以有正負號、小數點、e 指數。「-5-3」「1.5.5」這種黏在一起的也分得開
    mutating func number() -> Double? {
        skipSep()
        let begin: Int = i
        var j: Int = i
        if j < s.count && (s[j] == 0x2B || s[j] == 0x2D) {
            j += 1
        }
        var digits: Int = 0
        while j < s.count && SvgScanner.isDigit(s[j]) {
            j += 1
            digits += 1
        }
        if j < s.count && s[j] == 0x2E {
            j += 1
            while j < s.count && SvgScanner.isDigit(s[j]) {
                j += 1
                digits += 1
            }
        }
        if digits == 0 { return nil }
        // 指數：e 後面一定要接數字才算，不然那個 e 不是這個數字的
        if j < s.count && (s[j] == 0x65 || s[j] == 0x45) {
            var k: Int = j + 1
            if k < s.count && (s[k] == 0x2B || s[k] == 0x2D) {
                k += 1
            }
            var expDigits: Int = 0
            while k < s.count && SvgScanner.isDigit(s[k]) {
                k += 1
                expDigits += 1
            }
            if expDigits > 0 {
                j = k
            }
        }
        var text: String = String(decoding: s[begin..<j], as: UTF8.self)
        // Double("…") 不收「.5」「5.」「+5」這幾種寫法，先補成它看得懂的
        if text.hasPrefix("+") {
            text.removeFirst()
        }
        if text.hasPrefix(".") {
            text = "0" + text
        } else if text.hasPrefix("-.") {
            text = "-0" + String(text.dropFirst())
        }
        text = text.replacingOccurrences(of: ".e", with: ".0e").replacingOccurrences(of: ".E", with: ".0E")
        if text.hasSuffix(".") {
            text += "0"
        }
        guard let v = Double(text) else { return nil }
        i = j
        return v
    }

    /// 圓弧的兩個旗標：只會是 0 或 1，而且可以跟後面的數字黏在一起（「a1 1 0 01 2 2」）
    mutating func flag() -> Bool? {
        skipSep()
        guard i < s.count else { return nil }
        let c: UInt8 = s[i]
        if c == 0x30 {
            i += 1
            return false
        }
        if c == 0x31 {
            i += 1
            return true
        }
        return nil
    }
}

/// SVG 的圓弧（端點寫法）換成幾段三次貝茲曲線接上去。每段不超過四分之一圈
private func svgArc(
    _ path: inout Path, _ x0: Double, _ y0: Double, _ rxIn: Double, _ ryIn: Double,
    _ rotDeg: Double, _ largeArc: Bool, _ sweep: Bool, _ x1: Double, _ y1: Double
) {
    if x0 == x1 && y0 == y1 { return }
    var rx: Double = abs(rxIn)
    var ry: Double = abs(ryIn)
    if rx == 0 || ry == 0 {
        path.addLine(to: CGPoint(x: x1, y: y1))
        return
    }
    let phi: Double = rotDeg * Double.pi / 180
    let cosP: Double = cos(phi)
    let sinP: Double = sin(phi)
    let dx2: Double = (x0 - x1) / 2
    let dy2: Double = (y0 - y1) / 2
    let x1p: Double = cosP * dx2 + sinP * dy2
    let y1p: Double = -sinP * dx2 + cosP * dy2
    // 半徑不夠長、兩端接不起來時，照規格把半徑等比例放大
    let lam: Double = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
    if lam > 1 {
        let grow: Double = lam.squareRoot()
        rx *= grow
        ry *= grow
    }
    let rx2: Double = rx * rx
    let ry2: Double = ry * ry
    let num: Double = rx2 * ry2 - rx2 * y1p * y1p - ry2 * x1p * x1p
    let den: Double = rx2 * y1p * y1p + ry2 * x1p * x1p
    var coef: Double = den == 0 ? 0 : max(0, num / den).squareRoot()
    if largeArc == sweep {
        coef = -coef
    }
    let cxp: Double = coef * rx * y1p / ry
    let cyp: Double = -coef * ry * x1p / rx
    let cx: Double = cosP * cxp - sinP * cyp + (x0 + x1) / 2
    let cy: Double = sinP * cxp + cosP * cyp + (y0 + y1) / 2
    let theta1: Double = atan2((y1p - cyp) / ry, (x1p - cxp) / rx)
    let theta2: Double = atan2((-y1p - cyp) / ry, (-x1p - cxp) / rx)
    var delta: Double = theta2 - theta1
    if !sweep && delta > 0 {
        delta -= 2 * Double.pi
    } else if sweep && delta < 0 {
        delta += 2 * Double.pi
    }
    let n: Int = max(1, Int((abs(delta) / (Double.pi / 2)).rounded(.up)))
    let step: Double = delta / Double(n)
    let t: Double = 4.0 / 3.0 * tan(step / 4)
    for seg in 0..<n {
        let a1: Double = theta1 + Double(seg) * step
        let a2: Double = a1 + step
        let c1: Double = cos(a1)
        let s1: Double = sin(a1)
        let c2: Double = cos(a2)
        let s2: Double = sin(a2)
        // 橢圓上的點，和那一點的切線方向
        let p1x: Double = cx + rx * c1 * cosP - ry * s1 * sinP
        let p1y: Double = cy + rx * c1 * sinP + ry * s1 * cosP
        let d1x: Double = -rx * s1 * cosP - ry * c1 * sinP
        let d1y: Double = -rx * s1 * sinP + ry * c1 * cosP
        var p2x: Double = cx + rx * c2 * cosP - ry * s2 * sinP
        var p2y: Double = cy + rx * c2 * sinP + ry * s2 * cosP
        let d2x: Double = -rx * s2 * cosP - ry * c2 * sinP
        let d2y: Double = -rx * s2 * sinP + ry * c2 * cosP
        let ctrl1: CGPoint = CGPoint(x: p1x + t * d1x, y: p1y + t * d1y)
        let ctrl2: CGPoint = CGPoint(x: p2x - t * d2x, y: p2y - t * d2y)
        if seg == n - 1 {
            // 最後一段的終點直接用指定的終點，免得小數誤差讓線接不起來
            p2x = x1
            p2y = y1
        }
        path.addCurve(to: CGPoint(x: p2x, y: p2y), control1: ctrl1, control2: ctrl2)
    }
}

/// 把 SVG 的 path 字串（`M12 12C9 9 …`）變成 Path。
/// 支援 M m L l H h V v C c S s Q q T t A a Z z；指令可以省略重複（M 後面多的座標當 L）；
/// 數字之間用逗號或空白分，負號可以直接接在前一個數字後面；圓弧用貝茲曲線近似。
/// 讀到看不懂的地方就停，回傳到那裡為止畫好的部分。
func svgPath(_ d: String) -> Path {
    var path: Path = Path()
    var sc: SvgScanner = SvgScanner(d)
    var cmd: UInt8 = 0
    // 現在的位置、這一段的起點
    var cx: Double = 0
    var cy: Double = 0
    var sx: Double = 0
    var sy: Double = 0
    // 上一個指令的控制點，S/s、T/t 要拿來對稱。0 沒有、1 三次、2 二次
    var lastKind: Int = 0
    var lcx: Double = 0
    var lcy: Double = 0
    // Z 之後沒有 M 就接著畫：要先在起點落筆
    var needMove: Bool = true

    while true {
        sc.skipSep()
        if sc.atEnd { break }
        if let c = sc.command() {
            cmd = c
        } else {
            // 沒有新指令：重複上一個。M 之後的當 L，m 之後的當 l；Z 不能重複
            if cmd == 0x4D {
                cmd = 0x4C
            } else if cmd == 0x6D {
                cmd = 0x6C
            } else if cmd == 0 || cmd == 0x5A || cmd == 0x7A {
                break
            }
        }
        let rel: Bool = cmd >= 0x61
        let bx: Double = rel ? cx : 0
        let by: Double = rel ? cy : 0
        var kind: Int = 0

        switch cmd {
        case 0x4D, 0x6D:  // M m
            guard let x = sc.number(), let y = sc.number() else { return path }
            cx = bx + x
            cy = by + y
            sx = cx
            sy = cy
            path.move(to: CGPoint(x: cx, y: cy))
            needMove = false
        case 0x5A, 0x7A:  // Z z
            if !needMove {
                path.closeSubpath()
            }
            cx = sx
            cy = sy
            needMove = true
        default:
            if needMove {
                path.move(to: CGPoint(x: cx, y: cy))
                sx = cx
                sy = cy
                needMove = false
            }
            switch cmd {
            case 0x4C, 0x6C:  // L l
                guard let x = sc.number(), let y = sc.number() else { return path }
                cx = bx + x
                cy = by + y
                path.addLine(to: CGPoint(x: cx, y: cy))
            case 0x48, 0x68:  // H h
                guard let x = sc.number() else { return path }
                cx = bx + x
                path.addLine(to: CGPoint(x: cx, y: cy))
            case 0x56, 0x76:  // V v
                guard let y = sc.number() else { return path }
                cy = by + y
                path.addLine(to: CGPoint(x: cx, y: cy))
            case 0x43, 0x63:  // C c
                guard let x1 = sc.number(), let y1 = sc.number(),
                    let x2 = sc.number(), let y2 = sc.number(),
                    let x = sc.number(), let y = sc.number()
                else { return path }
                path.addCurve(
                    to: CGPoint(x: bx + x, y: by + y),
                    control1: CGPoint(x: bx + x1, y: by + y1),
                    control2: CGPoint(x: bx + x2, y: by + y2)
                )
                lcx = bx + x2
                lcy = by + y2
                kind = 1
                cx = bx + x
                cy = by + y
            case 0x53, 0x73:  // S s
                guard let x2 = sc.number(), let y2 = sc.number(),
                    let x = sc.number(), let y = sc.number()
                else { return path }
                // 第一個控制點是上一個三次曲線第二控制點的對稱點；上一個不是三次曲線就用現在的位置
                let r1x: Double = lastKind == 1 ? 2 * cx - lcx : cx
                let r1y: Double = lastKind == 1 ? 2 * cy - lcy : cy
                path.addCurve(
                    to: CGPoint(x: bx + x, y: by + y),
                    control1: CGPoint(x: r1x, y: r1y),
                    control2: CGPoint(x: bx + x2, y: by + y2)
                )
                lcx = bx + x2
                lcy = by + y2
                kind = 1
                cx = bx + x
                cy = by + y
            case 0x51, 0x71:  // Q q
                guard let x1 = sc.number(), let y1 = sc.number(),
                    let x = sc.number(), let y = sc.number()
                else { return path }
                path.addQuadCurve(
                    to: CGPoint(x: bx + x, y: by + y),
                    control: CGPoint(x: bx + x1, y: by + y1)
                )
                lcx = bx + x1
                lcy = by + y1
                kind = 2
                cx = bx + x
                cy = by + y
            case 0x54, 0x74:  // T t
                guard let x = sc.number(), let y = sc.number() else { return path }
                let qx: Double = lastKind == 2 ? 2 * cx - lcx : cx
                let qy: Double = lastKind == 2 ? 2 * cy - lcy : cy
                path.addQuadCurve(
                    to: CGPoint(x: bx + x, y: by + y),
                    control: CGPoint(x: qx, y: qy)
                )
                lcx = qx
                lcy = qy
                kind = 2
                cx = bx + x
                cy = by + y
            case 0x41, 0x61:  // A a
                guard let rx = sc.number(), let ry = sc.number(), let rot = sc.number(),
                    let large = sc.flag(), let sweep = sc.flag(),
                    let x = sc.number(), let y = sc.number()
                else { return path }
                svgArc(&path, cx, cy, rx, ry, rot, large, sweep, bx + x, by + y)
                cx = bx + x
                cy = by + y
            default:
                // 不認得的指令
                return path
            }
        }
        lastKind = kind
    }
    return path
}

/// SVG 的 viewBox 放進一塊區域的轉換：等比例縮到剛好放得下，置中（SVG 預設的 xMidYMid meet）
func svgFit(_ box: CGRect, _ size: CGSize) -> CGAffineTransform {
    guard box.width > 0, box.height > 0 else { return CGAffineTransform.identity }
    let k: CGFloat = min(size.width / box.width, size.height / box.height)
    let dx: CGFloat = (size.width - box.width * k) / 2 - box.minX * k
    let dy: CGFloat = (size.height - box.height * k) / 2 - box.minY * k
    return CGAffineTransform(a: k, b: 0, c: 0, d: k, tx: dx, ty: dy)
}

// MARK: - 蘿蔔

private let RADISH_LEAF: Path = svgPath("M12 12C9 9 6 6 5 2c4 1 6 4 7 8 1-4 3-7 7-8-1 4-4 7-7 10z")
private let RADISH_BODY_L: Path = svgPath("M6 14c0-3 3-4 6-4s6 1 6 4c0 8-3 18-6 18S6 22 6 14z")
private let RADISH_BODY_S: Path = svgPath("M7 15c0-2 2-3 5-3s5 1 5 3c0 6-3 16-5 16S7 21 7 15z")
private let RADISH_MARKS_L: Path = svgPath("M9 17h3M13 22h2")
private let RADISH_MARKS_S: Path = svgPath("M9.5 18h3M12 23h2.5")
private let RADISH_BOX: CGRect = CGRect(x: 0, y: 0, width: 24, height: 34)

/// 大站是白蘿蔔、比較大；小站是橘蘿蔔、比較小
struct Radish: View {
    let size: StopSize
    let scale: CGFloat
    let faded: Bool

    init(size: StopSize, scale: CGFloat = 1, faded: Bool = false) {
        self.size = size
        self.scale = scale
        self.faded = faded
    }

    /// TS 的 DIM
    private var dim: CGSize {
        switch size {
        case .L: return CGSize(width: 26, height: 37)
        case .S: return CGSize(width: 20, height: 28)
        }
    }

    var body: some View {
        let isBig: Bool = size == .L
        return Canvas { (context: inout GraphicsContext, canvasSize: CGSize) in
            var g: GraphicsContext = context
            g.concatenate(svgFit(RADISH_BOX, canvasSize))
            g.fill(RADISH_LEAF, with: .color(RadishColors.leaf))
            if isBig {
                g.fill(RADISH_BODY_L, with: .color(RadishColors.big))
                g.stroke(
                    RADISH_BODY_L, with: .color(RadishColors.bigLine),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .butt, lineJoin: .miter, miterLimit: 4)
                )
                g.stroke(
                    RADISH_MARKS_L, with: .color(RadishColors.bigLine),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            } else {
                g.fill(RADISH_BODY_S, with: .color(RadishColors.small))
                g.stroke(
                    RADISH_MARKS_S, with: .color(RadishColors.smallLine),
                    style: StrokeStyle(lineWidth: 1, lineCap: .round)
                )
            }
        }
        .frame(width: dim.width * scale, height: dim.height * scale)
        .opacity(faded ? T.Motion.pressedOpacity : 1)
        .accessibilityHidden(true)
    }
}
