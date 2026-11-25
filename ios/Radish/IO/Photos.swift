// 照片：從相簿挑一張 → 縮到長邊 1280 → 存進 app 自己的資料夾。沒網路也看得到。
// 行程裡只記檔名，不記完整路徑。iOS 更新 app 之後資料夾的路徑會變，記完整路徑會找不到檔案。
// 用系統的 PhotosPicker 挑照片，不用問相簿權限（系統只把使用者挑的那一張交給 app）。
// 對應 mobile/src/io/photos.ts。
import ImageIO
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

    /// 不縮的時候讀多大：存的時候就縮到這麼大了
    static let fullPixels: Int = Int(maxEdge)

    /// 讀過的照片記在記憶體裡，捲回來不用再讀檔。手機記憶體不夠時系統會自己清
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.totalCostLimit = 64 * 1024 * 1024  // domy-ignore: 快取上限 64MB，不是介面尺寸
        return c
    }()

    private static func cacheKey(_ ref: String, _ pixels: Int) -> NSString {
        "\(ref)@\(pixels)" as NSString
    }

    /// 記憶體裡已經有的那一張。沒有就回 nil，不讀檔
    static func cached(_ ref: String, _ pixels: Int) -> UIImage? {
        cache.object(forKey: cacheKey(ref, pixels))
    }

    /// 讀出來顯示：在背景讀檔、縮到長邊 pixels 像素、先解碼好，畫面拿到就能直接畫。檔案不在就回 nil
    static func load(_ ref: String, _ pixels: Int) async -> UIImage? {
        if let hit = cached(ref, pixels) { return hit }
        let file: URL = url(ref)
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            decode(file, pixels)
        }.value
        if let image, let cg = image.cgImage {
            cache.setObject(image, forKey: cacheKey(ref, pixels), cost: cg.bytesPerRow * cg.height)
        }
        return image
    }

    /// 用系統的縮圖功能讀：不把整張原圖讀進記憶體，而且在這裡就解碼完，不留到畫面上才做
    private static func decode(_ file: URL, _ pixels: Int) -> UIImage? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(file as CFURL, sourceOptions) else { return nil }
        let thumbOptions: CFDictionary =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: pixels,
            ] as CFDictionary
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions) else { return nil }
        return UIImage(cgImage: cg)
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

    /// 拿掉的照片：檔名先記在這裡，檔案不動，所以拿掉可以復原
    private static let pendingKey: String = "radish-photos-to-remove"

    /// 記下「下次開 app 再刪」。只記檔名
    static func removeLater(_ ref: String) {
        var list: [String] = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        if list.contains(ref) { return }
        list.append(ref)
        UserDefaults.standard.set(list, forKey: pendingKey)
    }

    /// 現在用得到的照片從清單移出來。復原之後、整包換掉之前叫：
    /// 拿掉又復原的照片，之後全部清掉、重開 app 也不會被刪
    static func keepUsed(_ s: AppState) {
        let list: [String] = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        if list.isEmpty { return }
        let used: Set<String> = refs(s)
        let left: [String] = list.filter { (ref: String) -> Bool in !used.contains(ref) }
        if left.count == list.count { return }
        UserDefaults.standard.set(left, forKey: pendingKey)
    }

    /// 刪掉記下來的那幾張。只在剛開 app、讀完檔的時候叫（復原紀錄這時候是空的）。
    /// 只看清單裡的檔名，不掃資料夾。存檔讀不出來就一張都不刪，清單留到下次。
    /// 復原回來、現在還用得到的不刪，從清單拿掉
    static func sweepRemoved(_ s: AppState, file: URL) {
        let list: [String] = UserDefaults.standard.stringArray(forKey: pendingKey) ?? []
        if list.isEmpty { return }
        guard let main = try? Data(contentsOf: file), AppState.hydrate(main) != nil else { return }
        guard let texts = savedTexts(file) else { return }
        let used: Set<String> = refs(s)
        var left: [String] = []
        for ref in list {
            // 只認自己存的檔名，空的或帶路徑的一律不碰
            if !ref.hasSuffix(".jpg") || ref.contains("/") { continue }
            if used.contains(ref) { continue }
            let inText: Bool = texts.contains { (t: String) -> Bool in t.contains(ref) }
            if inText { continue }
            let at: URL = url(ref)
            try? FileManager.default.removeItem(at: at)
            if FileManager.default.fileExists(atPath: at.path) { left.append(ref) }
        }
        UserDefaults.standard.set(left, forKey: pendingKey)
    }

    /// 存檔和以前讀不出來另外留著的那幾份，原本的字。有一份讀不到就回 nil（那就先不刪）
    private static func savedTexts(_ file: URL) -> [String]? {
        let dir: URL = file.deletingLastPathComponent()
        let stem: String = file.deletingPathExtension().lastPathComponent
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return nil }
        var out: [String] = []
        for name in names where name.hasPrefix(stem) {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
            out.append(String(decoding: data, as: UTF8.self))
        }
        return out
    }

    /// 現在用得到的照片：這趟、放一邊的、去過的、下次再來的站，連封面
    private static func refs(_ s: AppState) -> Set<String> {
        var out: Set<String> = []
        var trips: [Trip] = s.shelf.map { (x: Shelved) -> Trip in x.trip }
        if let trip = s.trip { trips.append(trip) }
        for b in s.baskets {
            if let trip = b.trip { trips.append(trip) }
        }
        for t in trips {
            if let cover = t.cover { out.insert(cover) }
            for slot in t.slots {
                for it in slot.items { out.formUnion(it.photos ?? []) }
            }
        }
        for b in s.baskets {
            if let cover = b.cover { out.insert(cover) }
            for it in b.items { out.formUnion(it.photos ?? []) }
        }
        for seed in s.seeds { out.formUnion(seed.stop?.photos ?? []) }
        return out
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
        PhotoImage(ref: ref, edge: edge)
            .frame(width: edge, height: edge)
            .clipShape(shape)
    }
}

/// 一張照片，裁滿外面給的框。在背景讀、縮成畫面用得到的大小，讀好之前和檔案讀不到時顯示灰底。
/// 外面要自己給 .frame 和 .clipShape
struct PhotoImage: View {
    let ref: String
    /// 這張在畫面上最長那一邊是幾點。nil 是不縮（整列寬的封面）
    var edge: CGFloat? = nil
    /// true：整張放進框裡（看大圖），不裁
    var fit: Bool = false

    @Environment(\.displayScale) private var scale: CGFloat
    @State private var got: UIImage?
    @State private var gotKey: String = ""

    private var pixels: Int {
        guard let edge else { return PhotoStore.fullPixels }
        return min(PhotoStore.fullPixels, Int((edge * scale).rounded(.up)))
    }

    var body: some View {
        let px: Int = pixels
        let key: String = "\(ref)@\(px)"
        let shown: UIImage? = (gotKey == key ? got : nil) ?? PhotoStore.cached(ref, px)
        ZStack {
            if let shown {
                Image(uiImage: shown).resizable().aspectRatio(contentMode: fit ? .fit : .fill)
            } else {
                C.surfaceMuted
            }
        }
        .task(id: key) {
            let image: UIImage? = await PhotoStore.load(ref, px)
            got = image
            gotKey = key
        }
    }
}

/// 「加照片」的按鈕：開系統相簿挑一張，存好後把檔名交給 onPicked
struct PhotoAddButton: View {
    let title: String
    var disabled: Bool = false
    let onPicked: (String) -> Void
    let onFailed: () -> Void

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
        PhotoPicker(disabled: disabled, onPicked: onPicked, onFailed: onFailed) { (busy: Bool) in
            Text(busy ? "處理中…" : title)
                .font(T.TypeScale.callout.font)
                .foregroundStyle(disabled || busy ? C.textDisabled : C.textPrimary)
                .padding(.horizontal, T.Space.s4)
                .frame(height: T.Size.buttonCompact)
                .background(C.surfaceMuted, in: Capsule())
                .frame(minHeight: T.Size.touch)
                .contentShape(Rectangle())
        }
    }
}

/// 開系統相簿挑一張、縮小存好，把檔名交給 onPicked。長什麼樣子由 label 決定，拿到的是「正在處理」。
/// 加照片的按鈕（PhotoAddButton）和一站頁的「上傳照片」方塊都用這一個，存照片只有 PhotoStore.save 一套
struct PhotoPicker<Face: View>: View {
    var disabled: Bool = false
    let onPicked: (String) -> Void
    let onFailed: () -> Void
    let label: (Bool) -> Face
    @State private var item: PhotosPickerItem?
    @State private var busy = false

    init(
        disabled: Bool = false,
        onPicked: @escaping (String) -> Void,
        onFailed: @escaping () -> Void = {},
        @ViewBuilder label: @escaping (Bool) -> Face
    ) {
        self.disabled = disabled
        self.onPicked = onPicked
        self.onFailed = onFailed
        self.label = label
    }

    var body: some View {
        PhotosPicker(selection: $item, matching: .images, photoLibrary: .shared()) {
            label(busy)
        }
        .disabled(disabled || busy)
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
