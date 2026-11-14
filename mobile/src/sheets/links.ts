// 跳到外部地圖。韓國當地找路用 Naver 地圖；沒裝就開網頁版。
import { Linking } from 'react-native';

const enc = encodeURIComponent;

export async function openNaver(q: string) {
  try {
    await Linking.openURL(`nmap://search?query=${enc(q)}&appname=radish-travel`);
  } catch {
    await Linking.openURL(`https://map.naver.com/p/search/${enc(q)}`).catch(() => {});
  }
}
export const openGoogle = (q: string) => Linking.openURL(`https://www.google.com/maps/search/?api=1&query=${enc(q)}`).catch(() => {});
export const openApple = (q: string) => Linking.openURL(`https://maps.apple.com/?q=${enc(q)}`).catch(() => {});
