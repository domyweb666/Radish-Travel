// 過敏告知卡：一段韓文，點餐前拿給店員看。沒網路也能用。
// app 沒有每家店的食材資料，所以做不到幫你排除，只能幫你把話講清楚。
// 對應 mobile/src/components/AllergyCard.tsx（RadishCore 裡已經有同名的資料型別 AllergyCard，所以畫面叫 AllergyCardView）。
import SwiftUI
import UIKit

struct AllergyCardView: View {
    let list: [String]
    @State private var copied: Bool = false

    init(list: [String]) {
        self.list = list
    }

    var body: some View {
        if let card = allergyCard(list) {
            Card {
                FieldLabel("給店員看（韓文）")
                DomyText(card.kr, .title2)
                    .accessibilityLabel("韓文告知卡。中文意思：\(card.zh)")
                FieldLabel("中文意思")
                DomyText(card.zh, .body)
                DomyButton(copied ? "複製了" : "複製韓文", variant: .secondary, size: .compact) {
                    UIPasteboard.general.string = card.kr
                    copied = true
                }
                .accessibilityIdentifier("allergy-copy")
                DomyText(
                    "未核對：這段韓文是照常見說法寫的，還沒請懂韓文的人看過。過敏嚴重的話，出發前請找懂韓文的人確認，或帶醫師開的說明。",
                    .footnote, tone: .secondary)
            }
        }
    }
}
