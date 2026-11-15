// 照片：從相簿挑一張 → 縮到長邊 1280 → 存進 app 自己的資料夾。沒網路也看得到。
// 行程裡只記檔名，不記完整路徑。iOS 更新 app 之後資料夾的路徑會變，記完整路徑會找不到檔案。
// 網頁預覽沒有檔案系統，直接記瀏覽器給的網址，重新整理後會不見；那只是拿來看版面的。
import { Directory, File, Paths } from 'expo-file-system';
import { ImageManipulator, SaveFormat } from 'expo-image-manipulator';
import * as ImagePicker from 'expo-image-picker';
import { Platform } from 'react-native';

const DIR = 'photos';
const MAX_EDGE = 1280;
const JPEG_QUALITY = 0.6;
/** 一站最多幾張 */
export const PHOTO_MAX = 6;

const isUrl = (ref: string) => ref.includes(':');

/** 把行程裡記的那個字串變成可以顯示的位置 */
export function photoUri(ref: string): string {
  return isUrl(ref) ? ref : new File(Paths.document, DIR, ref).uri;
}

/** 挑一張照片。回傳要記進行程的字串；使用者取消就回 null */
export async function pickPhoto(): Promise<string | null> {
  const res = await ImagePicker.launchImageLibraryAsync({ mediaTypes: ['images'], quality: 1 });
  if (res.canceled || !res.assets.length) return null;
  const asset = res.assets[0];
  const ctx = ImageManipulator.manipulate(asset.uri);
  const long = Math.max(asset.width, asset.height);
  if (long > MAX_EDGE) ctx.resize(asset.width >= asset.height ? { width: MAX_EDGE } : { height: MAX_EDGE });
  const saved = await (await ctx.renderAsync()).saveAsync({ compress: JPEG_QUALITY, format: SaveFormat.JPEG });
  if (Platform.OS === 'web') return saved.uri;
  const dir = new Directory(Paths.document, DIR);
  if (!dir.exists) dir.create();
  const name = `p${Date.now().toString(36)}${Math.floor(Math.random() * 1296).toString(36)}.jpg`;
  await new File(saved.uri).copy(new File(dir, name));
  return name;
}

/** 拿掉一張照片時把檔案也刪掉。刪不掉不影響行程 */
export function removePhotoFile(ref: string): void {
  if (isUrl(ref)) return;
  try {
    const f = new File(Paths.document, DIR, ref);
    if (f.exists) f.delete();
  } catch {
    // 檔案本來就不在了
  }
}

/** 讀成可以直接塞進網頁的資料網址。做地圖網頁時用 */
export async function photoDataUri(ref: string): Promise<string | null> {
  try {
    if (Platform.OS === 'web') {
      if (ref.startsWith('data:')) return ref;
      const blob = await (await fetch(ref)).blob();
      return await new Promise<string>((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result));
        r.onerror = () => reject(r.error);
        r.readAsDataURL(blob);
      });
    }
    return `data:image/jpeg;base64,${await new File(photoUri(ref)).base64()}`;
  } catch {
    return null;
  }
}

/** 把一份文字存成檔案，回傳檔案位置。分享地圖網頁時用（只在手機上） */
export async function writeTemp(name: string, text: string): Promise<string> {
  const f = new File(Paths.cache, name);
  if (f.exists) f.delete();
  f.create();
  await f.write(text);
  return f.uri;
}
