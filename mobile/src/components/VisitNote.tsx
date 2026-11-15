// 去過的一站可以留的東西：一句話、幾張照片。旅途中的站和已經收起來的旅行共用這一塊。
import { useEffect, useRef, useState } from 'react';
import { DomyButton, DomyText, DomyTextField } from '@domy/design';
import { PHOTO_MAX, pickPhoto, removePhotoFile } from '../io/photos';
import { useApp } from '../store';
import { PhotoStrip } from './PhotoStrip';
import { Card, Label } from './ui';

export function VisitNote({ say, photos, onSay, onPhotos }: { say?: string; photos: string[]; onSay: (text: string) => void; onPhotos: (next: string[]) => void }) {
  const app = useApp();
  const [adding, setAdding] = useState(false);
  const full = photos.length >= PHOTO_MAX;
  // 打到一半就按「好了」或「關閉」時，輸入框不一定來得及說它打完了。所以關掉這一塊的時候再存一次，打的字才不會不見。
  const typed = useRef(say ?? '');
  const saved = useRef(say ?? '');
  const save = useRef(onSay);
  save.current = onSay;
  const commit = () => {
    const v = typed.current.trim();
    if (v === saved.current) return;
    saved.current = v;
    save.current(v);
  };
  useEffect(() => commit, []); // eslint-disable-line react-hooks/exhaustive-deps
  return (
    <>
      <DomyTextField
        label="這裡最想講的一件事"
        helper="一句就好，不寫也可以。會收在「旅行」裡這一趟的去過的。"
        placeholder="例如：湯比想像中清"
        maxLength={60}
        defaultValue={say ?? ''}
        onChangeText={(v) => void (typed.current = v)}
        onEndEditing={commit}
      />
      <Card>
        <Label>照片</Label>
        <PhotoStrip
          refs={photos}
          onRemove={(ref) => {
            onPhotos(photos.filter((p) => p !== ref));
            removePhotoFile(ref);
          }}
        />
        <DomyButton
          title={adding ? '處理中…' : full ? `最多 ${PHOTO_MAX} 張` : '從相簿加一張'}
          variant="secondary"
          size="compact"
          style={{ alignSelf: 'flex-start' }}
          disabled={adding || full}
          onPress={() => {
            setAdding(true);
            pickPhoto()
              .then((ref) => {
                if (ref) onPhotos([...photos, ref]);
              })
              .catch(() => app.say('這張照片加不進來，換一張試試。'))
              .finally(() => setAdding(false));
          }}
        />
        <DomyText variant="footnote" tone="secondary">
          照片會縮小後存在這支手機裡，沒網路也看得到。不會上傳到任何地方。
        </DomyText>
      </Card>
    </>
  );
}
