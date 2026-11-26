// 平常的我「排序和連結」點開的那一頁：要先訂的站列哪幾個連結、哪些有分潤、排行程跟分潤無關。
// 連結旁邊不寫分潤，在這裡講一次（docs/聯盟連結-排序規則-草案.md 第四節）。
// 「價格跟自己去買一樣」要等多米確認兩家的聯盟條款才能寫，現在不寫。
import SwiftUI

struct BuyLinksAbout: View {
    let onClose: () -> Void

    var body: some View {
        SheetScaffold("排序和連結", onClose: onClose) {
            DomyText("要先訂的站，會列出官網、Klook、KKday，順序固定，不看哪家便宜。我們沒有即時價格，所以不寫哪家最便宜。", .body)
            DomyText("透過 Klook、KKday 的連結買，蘿蔔旅行會拿到一點分潤。官網沒有分潤，放在第一個，不經過我們也買得到。", .body)
            DomyText("哪一站排進這趟、排在哪，跟有沒有分潤無關。排這趟的時候不會看這些連結，問 AI 的時候 AI 也不知道哪一站有分潤。", .body)
        }
        .presentationDetents([.medium, .large])
    }
}
