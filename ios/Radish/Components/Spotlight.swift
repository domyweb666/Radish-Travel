// 原本是第一趟排好後的三步操作說明（把畫面蓋暗、只留一塊亮的），對應 mobile/src/components/Spotlight.tsx。
// 2026-11-23 片 2 拿掉了：02-流程 1-4 建議刪（❓38），改成讓每站那行和講的那一列自己帶出能做什麼；
// 方向說明 A17 也寫「跟著 1-4 刪操作說明」，平常的我的「再看一次操作說明」一起拿掉。
// 留下來的只有記位置的這一小段：TripScreenParts.swift 的 TripDayCard 還用 .spotTarget 給每一站一個捲動用的 id。
// 那邊不用了就可以整個檔刪掉。
import SwiftUI

/// 每一塊現在在螢幕上的框（global 座標）。不是畫面狀態，改它不會讓畫面重畫
final class SpotFrames {
    var rects: [String: CGRect] = [:]
}

extension View {
    /// 加上捲動用的 id，位置一變就記到 frames 裡
    func spotTarget(_ key: String, in frames: SpotFrames) -> some View {
        self
            .id(key)
            .onGeometryChange(for: CGRect.self) { (proxy: GeometryProxy) -> CGRect in
                return proxy.frame(in: .global)
            } action: { (rect: CGRect) in
                frames.rects[key] = rect
            }
    }
}
