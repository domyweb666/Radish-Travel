// 一排照片縮圖，可以左右滑。給 onRemove 的話每張下面多一顆「拿掉」。
import { Image, ScrollView, View } from 'react-native';
import { DomyButton, T } from '@domy/design';
import { photoUri } from '../io/photos';

const EDGE = T.size.heroButton / 2;

export function PhotoStrip({ refs, onRemove }: { refs: string[]; onRemove?: (ref: string) => void }) {
  if (!refs.length) return null;
  return (
    <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: T.space[2] }}>
      {refs.map((r, i) => (
        <View key={r} style={{ alignItems: 'center', gap: T.space[1] }}>
          <Image source={{ uri: photoUri(r) }} accessibilityLabel={`第 ${i + 1} 張照片`} style={{ width: EDGE, height: EDGE, borderRadius: T.radius.md }} />
          {onRemove ? <DomyButton title="拿掉" variant="plain" size="compact" onPress={() => onRemove(r)} /> : null}
        </View>
      ))}
    </ScrollView>
  );
}
