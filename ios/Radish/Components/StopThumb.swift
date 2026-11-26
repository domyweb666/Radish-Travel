// 這趟那天清單上一站的小縮圖：這一站有自己加的照片，就放第一張（QC-0013 #100）。沒有照片什麼都不畫，不佔位置。
// 照片在 Stop.photos，讀檔和縮小照 IO/Photos.swift 的 PhotoThumb。mobile/ 沒有對應的 TS。
import SwiftUI

struct StopThumb: View {
    let stop: Stop

    var body: some View {
        if let ref = stop.photos?.first {
            PhotoThumb(ref: ref, edge: T.Size.touch)
                .accessibilityHidden(true)
        }
    }
}
