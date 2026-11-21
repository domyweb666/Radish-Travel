// 「行前」的第三段，回程：買什麼回去、哪些不能帶、行李怎麼裝。
// 對應 mobile/src/screens/PrepScreen.tsx 的 Back。
import SwiftUI

/// 回程：買什麼回去、哪些不能帶、行李怎麼裝。全部還沒核對，畫面上要講清楚
struct PrepBack: View {
    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s6) {
            Banner("這一段是先整理的清單，還沒逐條核對，也還沒附來源。哪裡買、多少錢、能不能帶，買之前自己查一下。")
            PrepPickList(title: "伴手禮", items: GIFTS)
            DomySection("裝行李箱之前", footer: "入境規定會改，回程前請看農業部動植物防疫檢疫署和財政部關務署的官方頁。") {
                ForEach(Array(GIFT_RULES.enumerated()), id: \.offset) { _, r in
                    TextRow(r, note: "未核對")
                }
            }
        }
    }
}
