// 本機通知：只用來提醒「要先訂的還沒訂」。不連網路、不送任何資料出去。
// 權限只在使用者按了「出發前提醒我」之後才問。
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';
import type { Reminder } from '../domain/remind';

const supported = Platform.OS !== 'web';
const HOUR = 9; // 早上九點提醒

if (supported) {
  // app 開著的時候也照樣顯示
  Notifications.setNotificationHandler({
    handleNotification: async () => ({ shouldShowBanner: true, shouldShowList: true, shouldPlaySound: false, shouldSetBadge: false }),
  });
}

export type AskResult = 'ok' | 'denied' | 'unsupported';

export async function askReminders(): Promise<AskResult> {
  if (!supported) return 'unsupported';
  try {
    const cur = await Notifications.getPermissionsAsync();
    if (cur.granted) return 'ok';
    if (!cur.canAskAgain) return 'denied';
    return (await Notifications.requestPermissionsAsync()).granted ? 'ok' : 'denied';
  } catch {
    return 'denied';
  }
}

/** 把排好的通知整批換成這一份。這個 app 沒有別種通知，所以先全部取消再重排 */
export async function syncReminders(list: Reminder[]): Promise<void> {
  if (!supported) return;
  try {
    await Notifications.cancelAllScheduledNotificationsAsync();
    for (const r of list) {
      const [y, m, d] = r.on.split('-').map(Number);
      await Notifications.scheduleNotificationAsync({
        content: { title: r.title, body: r.body },
        trigger: { type: Notifications.SchedulableTriggerInputTypes.DATE, date: new Date(y, m - 1, d, HOUR) },
      });
    }
  } catch {
    // 排不成不影響其他功能；「這趟」頁上的提醒條還在
  }
}
