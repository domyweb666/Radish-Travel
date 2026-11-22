// 給司機看（S09，線框 .uiux/03-線框/線框/A11-Driver）：全螢幕，把韓文名稱放到最大，下面一句「請到這裡」。
// 從一站（StopScreen）和下一站卡（TripScreenParts.swift）用 .fullScreenCover 開。沒有韓文名稱的站不會出現入口。
// 原本是 mobile/src/sheets/StopSheet.tsx 的 show 那一面。
import SwiftUI

struct DriverView: View {
    @Environment(\.dismiss) private var dismiss
    /// 韓文名稱跟著系統字級變大，最大字級時名字長的會換行或縮小，不會被切掉
    @ScaledMetric(relativeTo: .largeTitle) private var krSize: CGFloat = 96  // domy-ignore: 線框 A11 的大字，只有這一頁用
    private let name: String
    private let kr: String

    init(name: String, kr: String) {
        self.name = name
        self.kr = kr
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DomyIconButton(title: "關閉", label: "關閉", neutral: true) {
                    dismiss()
                }
                .accessibilityIdentifier("driver-close")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, T.Space.s3)
            Spacer(minLength: T.Space.s4)
            words
            Spacer(minLength: T.Space.s4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(C.canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("driver-view")
    }

    private var words: some View {
        VStack(spacing: T.Space.s3) {
            DomyText(name, .subheadline, tone: .secondary, align: .center)
            Text(kr)
                .font(.system(size: krSize, weight: .bold))  // domy-ignore: 給司機看的大字，T.TypeScale 最大是 34
                .foregroundStyle(C.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.3)  // domy-ignore: 名字長的站（例：동대문디자인플라자）縮到放得下
                .accessibilityLabel("韓文名稱：\(kr)")
            VStack(spacing: T.Space.s2) {
                DomyText("여기로 가 주세요", .largeTitle, align: .center)
                DomyText("（請到這裡）", .body, tone: .secondary, align: .center)
            }
            .padding(.top, T.Space.s6)
        }
        .padding(.horizontal, T.Size.screenMargin)
        .frame(maxWidth: .infinity)
    }
}
