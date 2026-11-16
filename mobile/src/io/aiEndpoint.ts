// AI 端點的實際網址。正式版是完整網址，原樣回傳。
// 測試階段設成 /__ai（開發伺服器自己接，看 dev/ai-cli.js），手機上要補開發伺服器的位址，網頁版瀏覽器自己會補。
import { NativeModules, Platform } from 'react-native';
import { AI_ENDPOINT } from '../domain/chat';

export function aiEndpoint(): string {
  if (!AI_ENDPOINT.startsWith('/') || Platform.OS === 'web') return AI_ENDPOINT;
  const src = NativeModules.SourceCode as { scriptURL?: string; getConstants?: () => { scriptURL?: string } } | undefined;
  const url = src?.getConstants?.().scriptURL ?? src?.scriptURL ?? '';
  const origin = url.match(/^https?:\/\/[^/]+/)?.[0];
  return origin ? origin + AI_ENDPOINT : '';
}
