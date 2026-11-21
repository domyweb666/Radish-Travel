// 「行前」的第二段，在當地：跟台灣不一樣的、當地人的地雷、吃什麼、出事打哪裡。
// 對應 mobile/src/screens/PrepScreen.tsx 的 There。
import SwiftUI

/// 在當地：跟台灣不一樣的、當地人的地雷、吃什麼、出事打哪裡
struct PrepThere: View {
    @Environment(AppStore.self) private var store

    private let levels: [Int] = [3, 2, 1]  // domy-ignore: 地雷的等級，不是版面數值

    private var allFacts: [Fact] {
        let taboo: [Fact] = TABOO.map { (r: TabooFact) -> Fact in prepFact(r) }
        return DIFF + taboo + SOS
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s6) {
            allergySection
            PrepFactList(title: "跟台灣不一樣的地方", facts: DIFF)
            ForEach(levels, id: \.self) { (lv: Int) in
                tabooSection(lv)
            }
            PrepPickList(title: "到首爾多半會吃的", items: EATS)
            PrepPickList(
                title: "比較特別、敢吃再試的", items: DISHES,
                footer: "吃的這兩段是先整理的清單，還沒逐條核對，也沒有附來源。店家和價格去之前自己查。")
            PrepFactList(title: "出事的時候打這些電話", facts: SOS)
            PrepSourcesButton(title: "在當地這一段的來源", facts: allFacts)
        }
    }

    @ViewBuilder private var allergySection: some View {
        let allergy: [String] = store.s.settings.allergy
        if !allergy.isEmpty {
            DomySection(
                "你有過敏：\(allergy.joined(separator: "、"))",
                footer: "我不知道每家店用了哪些食材，沒辦法幫你排除。點餐前拿給店員看，自己確認。"
            ) {
                AllergyCardView(list: allergy)
            }
        }
    }

    private func tabooSection(_ lv: Int) -> some View {
        let rows: [TabooFact] = TABOO.filter { (r: TabooFact) -> Bool in r.level == lv }
        return DomySection("當地人的地雷：\(TABOO_LEVEL[need: lv])") {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                TextRow(r.text, note: prepNote(r.result))
            }
        }
    }
}
