// 照片：從相簿挑一張 → 縮到長邊 1280 → 存進 app 自己的資料夾。沒網路也看得到。
// 行程裡只記檔名，不記完整路徑。iOS 更新 app 之後資料夾的路徑會變，記完整路徑會找不到檔案。
// 用系統的 PhotosPicker 挑照片，不用問相簿權限（系統只把使用者挑的那一張交給 app）。
// 對應 mobile/src/io/photos.ts。
import PhotosUI
import SwiftUI
import UIKit

enum PhotoStore {
    private static let dirName = "photos"
    private static let maxEdge: CGFloat = 1280  // domy-ignore: 照片長邊的像素，不是介面尺寸
    private static let jpegQuality: CGFloat = 0.6  // domy-ignore: 壓縮品質
    /// 一站最多幾張
    static let max = 6

    private static var dir: URL {
        let base: URL =
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent(dirName, isDirectory: true)
    }

    /// 把行程裡記的那個檔名變成檔案位置
    static func url(_ ref: String) -> URL {
        dir.appendingPathComponent(ref)
    }

    /// 讀出來顯示。檔案不在就回 nil
    static func image(_ ref: String) -> UIImage? {
        UIImage(contentsOfFile: url(ref).path)
    }

    /// 把使用者挑的那一張縮小存起來。回傳要記進行程的檔名；失敗回 nil
    static func save(_ item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self),
            let source = UIImage(data: data)
        else { return nil }
        let long: CGFloat = Swift.max(source.size.width, source.size.height)
        let ratio: CGFloat = long > maxEdge ? maxEdge / long : 1
        let target = CGSize(width: source.size.width * ratio, height: source.size.height * ratio)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small: UIImage = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            source.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let jpeg = small.jpegData(compressionQuality: jpegQuality) else { return nil }
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000), radix: 36)
        let salt = String(Int.random(in: 0..<1296), radix: 36)
        let name = "p\(stamp)\(salt).jpg"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try jpeg.write(to: url(name), options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// 拿掉一張照片時把檔案也刪掉。刪不掉不影響行程
    static func remove(_ ref: String) {
        try? FileManager.default.removeItem(at: url(ref))
    }

    /// 讀成可以直接塞進網頁的資料網址。做地圖網頁時用
    static func dataUri(_ ref: String) -> String? {
        guard let data = try? Data(contentsOf: url(ref)) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    /// 把一份文字存成暫存檔，回傳檔案位置。分享地圖網頁時用
    static func writeTemp(_ name: String, _ text: String) -> URL? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try text.write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            return nil
        }
    }
}

/// 一排照片縮圖，可以左右滑。給 onRemove 的話每張下面多一顆「拿掉」。
struct PhotoStrip: View {
    let refs: [String]
    var onRemove: ((String) -> Void)?

    init(refs: [String], onRemove: ((String) -> Void)? = nil) {
        self.refs = refs
        self.onRemove = onRemove
    }

    var body: some View {
        let edge: CGFloat = T.Size.heroButton / 2
        if !refs.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: T.Space.s2) {
                    ForEach(Array(refs.enumerated()), id: \.element) { index, ref in
                        VStack(spacing: T.Space.s1) {
                            PhotoThumb(ref: ref, edge: edge)
                                .accessibilityLabel("第 \(index + 1) 張照片")
                            if let onRemove {
                                DomyButton("拿掉", variant: .plain, size: .compact) { onRemove(ref) }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// 一張方形縮圖。檔案讀不到時顯示灰底，不讓版面跳掉
struct PhotoThumb: View {
    let ref: String
    let edge: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: T.Radius.md, style: .continuous)
        Group {
            if let image = PhotoStore.image(ref) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                C.surfaceMuted
            }
        }
        .frame(width: edge, height: edge)
        .clipShape(shape)
    }
}

/// 「加照片」的按鈕：開系統相簿挑一張，存好後把檔名交給 onPicked
struct PhotoAddButton: View {
    let title: String
    var disabled: Bool = false
    let onPicked: (String) -> Void
    let onFailed: () -> Void
    @State private var item: PhotosPickerItem?
    @State private var busy = false

    init(
        _ title: String = "加照片",
        disabled: Bool = false,
        onPicked: @escaping (String) -> Void,
        onFailed: @escaping () -> Void = {}
    ) {
        self.title = title
        self.disabled = disabled
        self.onPicked = onPicked
        self.onFailed = onFailed
    }

    var body: some View {
        let off: Bool = disabled || busy
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            Text(busy ? "處理中…" : title)
                .font(T.TypeScale.callout.font)
                .foregroundStyle(off ? C.textDisabled : C.textPrimary)
                .padding(.horizontal, T.Space.s4)
                .frame(height: T.Size.buttonCompact)
                .background(C.surfaceMuted, in: Capsule())
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
        }
        .disabled(off)
        .onChange(of: item) { _, picked in
            guard let picked else { return }
            busy = true
            Task {
                let name: String? = await PhotoStore.save(picked)
                busy = false
                item = nil
                if let name {
                    onPicked(name)
                } else {
                    onFailed()
                }
            }
        }
    }
}
