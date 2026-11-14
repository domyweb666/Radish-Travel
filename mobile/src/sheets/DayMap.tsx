// iPhone 上的地圖：用系統內建的 Apple 地圖元件。網頁預覽走 DayMap.web.tsx。
import * as Location from 'expo-location';
import { useRef, useState } from 'react';
import { View } from 'react-native';
import MapView, { Marker, Polyline } from 'react-native-maps';
import { DomyButton, DomyText, T, useDomy } from '@domy/design';

export interface MapPoint {
  key: string;
  title: string;
  subtitle?: string;
  lat: number;
  lng: number;
  home?: boolean;
}

const MAP_H = 380;
const PAD = 60;

export function DayMap({ points }: { points: MapPoint[] }) {
  const { c } = useDomy();
  const map = useRef<MapView>(null);
  const [me, setMe] = useState(false);
  const [denied, setDenied] = useState(false);
  const coords = points.map((p) => ({ latitude: p.lat, longitude: p.lng }));
  const fit = () => map.current?.fitToCoordinates(coords, { edgePadding: { top: PAD, right: PAD, bottom: PAD, left: PAD }, animated: true });
  const locate = async () => {
    const { status } = await Location.requestForegroundPermissionsAsync();
    if (status !== 'granted') {
      setDenied(true);
      return;
    }
    setMe(true);
    try {
      const pos = await Location.getCurrentPositionAsync({});
      map.current?.animateToRegion({ latitude: pos.coords.latitude, longitude: pos.coords.longitude, latitudeDelta: 0.02, longitudeDelta: 0.02 });
    } catch {
      // 拿不到位置就留在原本的畫面，藍點出現時使用者自己看得到
    }
  };
  return (
    <View style={{ gap: T.space[3] }}>
      <View style={{ height: MAP_H, borderRadius: T.radius.xl, overflow: 'hidden' }}>
        <MapView ref={map} style={{ flex: 1 }} showsUserLocation={me} onMapReady={fit}>
          <Polyline coordinates={coords} strokeColor={c.accent} strokeWidth={3} lineDashPattern={[2, 8]} />
          {points.map((p, i) => (
            <Marker key={p.key} coordinate={{ latitude: p.lat, longitude: p.lng }} title={p.home ? p.title : `${i}. ${p.title}`} description={p.subtitle} pinColor={p.home ? c.textPrimary : c.accent} />
          ))}
        </MapView>
      </View>
      <View style={{ flexDirection: 'row', gap: T.space[2] }}>
        <DomyButton title="我在哪" variant="secondary" size="compact" onPress={locate} />
        <DomyButton title="看整條路線" variant="secondary" size="compact" onPress={fit} />
      </View>
      {denied ? (
        <DomyText variant="footnote" tone="secondary">
          沒有拿到定位的允許。到 iPhone 的「設定 → 蘿蔔旅行 → 位置」打開，就能在地圖上看到自己。
        </DomyText>
      ) : null}
    </View>
  );
}
