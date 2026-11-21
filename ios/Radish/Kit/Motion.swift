// 動作代號表：全 app 的動畫曲線只從這裡取值，不准在畫面裡自己寫 .easeInOut(duration:)。
// 照 ios/手感指南.md 第四節：曲線用系統內建的 .snappy、.smooth、.bouncy。
// 拔蘿蔔那一段（PullMoment.swift）的節奏是逐毫秒照 Expo 版搬的，不走這張表。
//
// | 情境                                     | 動畫       | 震動                    |
// |------------------------------------------|------------|-------------------------|
// | 按壓可點元件                             | press      | 無                      |
// | 切分頁、切每天                           | 無         | Haptic.select()         |
// | 排好一趟、記一筆、存好設定               | change     | Haptic.notify(.success) |
// | 拿掉一站、刪一筆                         | change     | Haptic.impact(.light)   |
// | 其他資料變化（換一個、移動、打勾）       | change     | 無                      |
// | 出錯                                     | 無位移     | Haptic.notify(.error)   |
// | 提示條、浮層、捲到某一塊、地圖鏡頭       | transition | 無                      |
// | 數字變化                                 | change     | 無。DomyText 加 numeric: true |
// | 開關、選單                               | 系統自己的 | 不加，加了會重複        |
import SwiftUI

enum Motion {
    /// 按下、放開
    static let press = Animation.snappy(duration: T.Motion.pressDuration * 2)
    /// 資料變了：列表增減、數字換值、展開收合
    static let change = Animation.snappy
    /// 提示條、浮層進出、捲到某一塊、地圖鏡頭
    static let transition = Animation.smooth
    /// 完成的那一下
    static let celebrate = Animation.bouncy
}
