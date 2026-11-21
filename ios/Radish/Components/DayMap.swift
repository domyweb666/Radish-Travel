// iPhone 上的地圖：用系統內建的 Apple 地圖元件（MapKit 的 SwiftUI Map）。
// 對應 mobile/src/sheets/DayMap.tsx。定位只在按了「我在哪」之後才問，只問使用期間。
import CoreLocation
import MapKit
import Observation
import SwiftUI

struct MapPoint: Identifiable {
    var key: String
    var title: String
    var subtitle: String?
    var lat: Double
    var lng: Double
    var home: Bool?

    var id: String { key }

    init(key: String, title: String, subtitle: String? = nil, lat: Double, lng: Double, home: Bool? = nil) {
        self.key = key
        self.title = title
        self.subtitle = subtitle
        self.lat = lat
        self.lng = lng
        self.home = home
    }
}

private let MAP_H: CGFloat = 380  // domy-ignore: 地圖的高度，TS 的 MAP_H，只有這裡用
private let MAP_PAD: Double = 1.5  // domy-ignore: 看整條路線時四邊多留的比例（TS 是四邊各留 60 點）
private let MAP_MIN_SPAN: Double = 0.01  // domy-ignore: 只有一個點時至少看這麼大一塊（經緯度）
private let MAP_ME_SPAN: Double = 0.02  // domy-ignore: 移到「我在哪」時看多大一塊，TS 的 latitudeDelta
private let MAP_LINE: CGFloat = 3  // domy-ignore: 路線的線寬，TS 的 strokeWidth
private let MAP_DASH: [CGFloat] = [2, 8]  // domy-ignore: 虛線樣式，TS 的 lineDashPattern

/// 包住所有點、四邊留一點空的範圍。沒有點就回 nil
private func dayMapRegion(_ points: [MapPoint]) -> MKCoordinateRegion? {
    let lats: [Double] = points.map { (p: MapPoint) -> Double in p.lat }
    let lngs: [Double] = points.map { (p: MapPoint) -> Double in p.lng }
    guard let minLat = lats.min(), let maxLat = lats.max(), let minLng = lngs.min(), let maxLng = lngs.max() else {
        return nil
    }
    let center: CLLocationCoordinate2D = CLLocationCoordinate2D(
        latitude: (minLat + maxLat) / 2, longitude: (minLng + maxLng) / 2)
    let span: MKCoordinateSpan = MKCoordinateSpan(
        latitudeDelta: max((maxLat - minLat) * MAP_PAD, MAP_MIN_SPAN),
        longitudeDelta: max((maxLng - minLng) * MAP_PAD, MAP_MIN_SPAN))
    return MKCoordinateRegion(center: center, span: span)
}

private func dayMapCamera(_ points: [MapPoint]) -> MapCameraPosition {
    if let region = dayMapRegion(points) {
        return MapCameraPosition.region(region)
    }
    return MapCameraPosition.automatic
}

/// 問定位的允許、拿一次現在的位置。只在使用者按了「我在哪」之後才動
@MainActor
@Observable
final class MapLocator: NSObject, CLLocationManagerDelegate {
    /// 拿到允許了：地圖上顯示藍點（TS 的 me）
    var me: Bool = false
    /// 沒有拿到允許：顯示怎麼打開的說明
    var denied: Bool = false
    /// 最近一次拿到的位置
    var lat: Double? = nil
    var lng: Double? = nil
    /// 每拿到一次位置加一，畫面看它變了就把鏡頭移過去
    var tick: Int = 0

    @ObservationIgnored private let manager: CLLocationManager = CLLocationManager()
    /// 使用者按過「我在哪」了嗎。系統在一開始也會通知一次權限狀態，那一次不能當成使用者的回答
    @ObservationIgnored private var asked: Bool = false

    override init() {
        super.init()
        manager.delegate = self
    }

    func locate() {
        asked = true
        handle(manager.authorizationStatus)
    }

    private func handle(_ status: CLAuthorizationStatus) {
        switch status {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            me = true
            manager.requestLocation()
        case .denied, .restricted:
            denied = true
        @unknown default:
            denied = true
        }
    }

    private func authChanged(_ status: CLAuthorizationStatus) {
        if !asked || status == .notDetermined { return }
        handle(status)
    }

    private func got(_ latitude: Double, _ longitude: Double) {
        lat = latitude
        lng = longitude
        tick += 1
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status: CLAuthorizationStatus = manager.authorizationStatus
        Task { @MainActor in
            self.authChanged(status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        let latitude: Double = last.coordinate.latitude
        let longitude: Double = last.coordinate.longitude
        Task { @MainActor in
            self.got(latitude, longitude)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 拿不到位置就留在原本的畫面，藍點出現時使用者自己看得到
    }
}

struct DayMap: View {
    let points: [MapPoint]
    @State private var position: MapCameraPosition
    @State private var locator: MapLocator = MapLocator()

    init(points: [MapPoint]) {
        self.points = points
        self._position = State(initialValue: dayMapCamera(points))
    }

    private var coords: [CLLocationCoordinate2D] {
        points.map { (p: MapPoint) -> CLLocationCoordinate2D in
            CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: T.Space.s3) {
            map
                .frame(height: MAP_H)
                .clipShape(RoundedRectangle(cornerRadius: T.Radius.xl, style: .continuous))
            HStack(spacing: T.Space.s2) {
                DomyButton("我在哪", variant: .secondary, size: .compact) { locator.locate() }
                    .accessibilityIdentifier("map-locate")
                DomyButton("看整條路線", variant: .secondary, size: .compact) { fit() }
                    .accessibilityIdentifier("map-fit")
            }
            if locator.denied {
                DomyText("沒有拿到定位的允許。到 iPhone 的「設定 → 蘿蔔旅行 → 位置」打開，就能在地圖上看到自己。", .footnote, tone: .secondary)
            }
        }
        .onChange(of: locator.tick) { _, _ in goToMe() }
    }

    private var map: some View {
        let line: [CLLocationCoordinate2D] = coords
        let showMe: Bool = locator.me
        return Map(position: $position) {
            MapPolyline(coordinates: line)
                .stroke(C.accent, style: StrokeStyle(lineWidth: MAP_LINE, dash: MAP_DASH))
            ForEach(Array(points.enumerated()), id: \.element.id) { index, p in
                Marker(markerTitle(index, p), coordinate: CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng))
                    .tint(p.home == true ? C.textPrimary : C.accent)
            }
            if showMe {
                UserAnnotation()
            }
        }
        .accessibilityIdentifier("day-map")
    }

    private func markerTitle(_ index: Int, _ p: MapPoint) -> String {
        return p.home == true ? p.title : "\(index). \(p.title)"
    }

    /// 看整條路線：鏡頭調到包住所有點
    @MainActor
    private func fit() {
        let next: MapCameraPosition = dayMapCamera(points)
        withAnimation(.easeInOut(duration: T.Motion.transition)) {
            position = next
        }
    }

    /// 我在哪：拿到位置後把鏡頭移過去
    @MainActor
    private func goToMe() {
        guard let lat = locator.lat, let lng = locator.lng else { return }
        let region: MKCoordinateRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            span: MKCoordinateSpan(latitudeDelta: MAP_ME_SPAN, longitudeDelta: MAP_ME_SPAN))
        withAnimation(.easeInOut(duration: T.Motion.transition)) {
            position = MapCameraPosition.region(region)
        }
    }
}
