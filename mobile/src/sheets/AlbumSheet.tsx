// 一趟「去過的」：每一天去了哪、寫的那一句、照片。可以做成一頁有地圖的網頁檔傳給朋友。
// 現在這趟的站點一下會打開那一站（可以補一句、加照片）；已經收起來的旅行只能看。
import * as Sharing from 'expo-sharing';
import { useState } from 'react';
import { Platform, Pressable, View } from 'react-native';
import { DomyButton, DomyEmptyState, DomySection, DomyText, T } from '@domy/design';
import { albumHtml, type AlbumStop } from '../../album/albumHtml';
import { CatIcon, TabTrips } from '../components/icons';
import { PhotoStrip } from '../components/PhotoStrip';
import { Sheet } from '../components/Sheet';
import { addDays, fmtDay } from '../domain/dates';
import { tripTitle, visitedOf } from '../domain/tripActions';
import type { BasketItem } from '../domain/types';
import { photoDataUri, writeTemp } from '../io/photos';
import { useApp } from '../store';

export type AlbumSource = { from: 'current' } | { from: 'basket'; id: string };

export function AlbumSheet({ source, onClose, onOpenStop }: { source: AlbumSource; onClose: () => void; onOpenStop: (id: string) => void }) {
  const { s, say } = useApp();
  const [busy, setBusy] = useState(false);

  const basket = source.from === 'basket' ? s.baskets.find((b) => b.id === source.id) : undefined;
  const trip = source.from === 'current' ? s.trip : null;
  const title = basket?.title ?? (trip ? tripTitle(trip) : '');
  const start = basket?.start ?? trip?.start;
  const days = basket?.days ?? trip?.days;
  const items: BasketItem[] = basket?.items ?? (trip ? visitedOf(trip) : []);
  const dates = start && days ? `${fmtDay(start)}–${fmtDay(addDays(start, days - 1))}` : '';
  const dateOf = (day?: number) => (start && day ? fmtDay(addDays(start, day - 1)) : undefined);
  const groups = [...new Set(items.map((it) => it.day ?? 0))].sort((a, b) => a - b);

  const share = async () => {
    setBusy(true);
    try {
      const stops: AlbumStop[] = [];
      for (const it of items) {
        const photos = (await Promise.all((it.photos ?? []).map(photoDataUri))).filter((p): p is string => !!p);
        stops.push({ n: it.n, kr: it.kr, day: it.day, date: dateOf(it.day), say: it.say, lat: it.lat, lng: it.lng, photos });
      }
      const html = albumHtml({ title, dates, stops });
      if (Platform.OS === 'web') {
        const url = URL.createObjectURL(new Blob([html], { type: 'text/html' }));
        const a = document.createElement('a');
        a.href = url;
        a.download = 'radish-trip.html';
        a.click();
        URL.revokeObjectURL(url);
        say('網頁檔下載好了。');
      } else {
        const uri = await writeTemp('radish-trip.html', html);
        if (await Sharing.isAvailableAsync()) await Sharing.shareAsync(uri, { mimeType: 'text/html', UTI: 'public.html', dialogTitle: title });
        else say('這支手機沒辦法開分享選單。');
      }
    } catch {
      say('網頁檔沒做成功，等一下再試一次。');
    }
    setBusy(false);
  };

  return (
    <Sheet visible title={title || '去過的'} onClose={onClose}>
      {items.length ? (
        <>
          <DomyText variant="subheadline" tone="secondary">
            {dates ? `${dates}・` : ''}去了 {items.length} 個地方
          </DomyText>
          {groups.map((g) => (
            <DomySection key={g} title={g ? `第 ${g} 天${dateOf(g) ? '　' + dateOf(g) : ''}` : undefined}>
              {items
                .filter((it) => (it.day ?? 0) === g)
                .map((it, i) => (
                  <Pressable
                    key={`${it.n}${i}`}
                    accessibilityRole={it.id && trip ? 'button' : undefined}
                    disabled={!it.id || !trip}
                    onPress={() => it.id && onOpenStop(it.id)}
                    style={{ paddingVertical: T.space[3], gap: T.space[2] }}
                  >
                    <View style={{ flexDirection: 'row', alignItems: 'center', gap: T.space[3] }}>
                      <CatIcon it={it} />
                      <View style={{ flex: 1, gap: T.space[1] / 2 }}>
                        <DomyText variant="headline">{it.n}</DomyText>
                        <DomyText variant="subheadline" tone="secondary">
                          {it.say ? `「${it.say}」` : trip ? '點一下可以寫一句、加照片' : '沒有寫'}
                        </DomyText>
                      </View>
                    </View>
                    <PhotoStrip refs={it.photos ?? []} />
                  </Pressable>
                ))}
            </DomySection>
          ))}
          <DomyButton title={busy ? '正在做網頁檔…' : '做成地圖網頁，傳給朋友'} fullWidth disabled={busy} onPress={() => void share()} />
          <DomyText variant="footnote" tone="secondary">
            會做成一個網頁檔，上面是這趟的地圖，下面是每一站的那一句和照片，照片都包在檔案裡。朋友用瀏覽器就能開。有網路時地圖是可以縮放的真地圖，沒網路時是一張簡單的路線圖。照片多的話檔案會比較大。
          </DomyText>
        </>
      ) : (
        <DomyEmptyState icon={(color) => <TabTrips color={color} />} title="這趟還沒有去過的地方" body="旅途中每去過一站，按「去過了，拔起來」，它就會出現在這裡。" />
      )}
    </Sheet>
  );
}
