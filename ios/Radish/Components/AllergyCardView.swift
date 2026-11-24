// 過敏告知卡：一段韓文，點餐前拿給店員看。沒網路也能用。
// app 沒有每家店的食材資料，所以做不到幫你排除，只能幫你把話講清楚。
// 對應 mobile/src/components/AllergyCard.tsx（RadishCore 裡已經有同名的資料型別 AllergyCard，所以畫面叫 AllergyCardView）。
// 版面照線框 .uiux/03-線框/線框/A13-Allergy：韓文單獨一塊（給店員看的時候一眼看完），下面是中文意思、複製、未核對。
// 一站的半頁（S15）、檢查這趟、平常的我都用這一塊。沒設過敏就什麼都不顯示。
import SwiftUI
import UIKit

struct AllergyCardView: View {
    let list: [String]
    /// 複製過的那一段。清單改了，韓文就不一樣，按鈕要變回「複製韓文」
    @State private var copiedText: String = ""

    init(list: [String]) {
        self.list = list
    }

    var body: some View {
        if let card = allergyCard(list) {
            Card {
                korean(card)
                VStack(alignment: .leading, spacing: T.Space.s1) {
                    FieldLabel("中文意思")
                    DomyText(card.zh, .body)
                }
                DomyButton(copiedText == card.kr ? "複製了" : "複製韓文", variant: .secondary, size: .compact, fullWidth: true) {
                    UIPasteboard.general.string = card.kr
                    copiedText = card.kr
                }
                .accessibilityIdentifier("allergy-copy")
                DomyText(
                    "未核對：這段韓文是照常見說法寫的，還沒請懂韓文的人看過。過敏嚴重的話，出發前請找懂韓文的人確認，或帶醫師開的說明。",
                    .footnote, tone: .secondary)
            }
        }
    }

    private func korean(_ card: AllergyCard) -> some View {
        VStack(alignment: .leading, spacing: T.Space.s1) {
            FieldLabel("給店員看（韓文）")
            DomyText(card.kr, .title2)
                .accessibilityLabel("韓文告知卡。中文意思：\(card.zh)")
        }
        .padding(.vertical, T.Space.s3)
        .padding(.horizontal, T.Space.s4 - T.Space.s1 / 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(C.surfaceMuted, in: RoundedRectangle(cornerRadius: T.Radius.lg, style: .continuous))
    }
}
