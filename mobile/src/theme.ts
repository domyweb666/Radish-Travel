// 蘿蔔旅行的產品色：蘿蔔橘。只有這款 App 用，所以照 @domy/design README 的做法在 App 裡用 createTheme 建。
// 對比由 tests/theme.test.ts 用 auditTheme 驗，改色之後要跑 npm test。
import { createTheme } from '@domy/design/src/theme/createTheme';

export const radishTheme = createTheme({
  name: 'radish',
  label: '蘿蔔橘',
  canvas: 'warm',
  // domy-ignore: 產品色定義，唯一寫色碼的地方
  light: { accent: '#B5501B', onAccent: '#FFFFFF', strong: '#96400F', soft: '#F8E2D2', tint: '#FDF5EE', bright: '#FF9A3D', onBright: '#3A1A04' },
  // domy-ignore: 產品色定義，唯一寫色碼的地方
  dark: { accent: '#F0A064', onAccent: '#3A1A04', strong: '#F7BE93', soft: '#40281A', tint: '#221710', bright: '#FF9A3D', onBright: '#3A1A04' },
});

// 角色色：蘿蔔本身。它是內容，不是介面，淺深色都用同一組。
export const radishColors = {
  small: '#FF9A3D', // domy-ignore: 角色色，小站的橘蘿蔔
  smallLine: '#D9741C', // domy-ignore: 角色色
  big: '#FAFAF5', // domy-ignore: 角色色，大站的白蘿蔔
  bigLine: '#CFCFC4', // domy-ignore: 角色色
  leaf: '#4F9D5B', // domy-ignore: 角色色，葉子
  soil: '#C9A27A', // domy-ignore: 角色色，土
} as const;

// 蘿蔔人：戴蘿蔔頭套的火柴人。頭套沿用上面的橘蘿蔔和葉子。
export const buddyColors = {
  ink: '#2B2329', // domy-ignore: 角色色，五官
  face: '#FFFFFF', // domy-ignore: 角色色，臉
  faceRim: '#B85F12', // domy-ignore: 角色色，臉外圈
  shine: '#FFC48A', // domy-ignore: 角色色，頭套反光
  leafDark: '#3B7F47', // domy-ignore: 角色色，中間那片葉子
  sweat: '#7EC3EA', // domy-ignore: 角色色，汗
} as const;
