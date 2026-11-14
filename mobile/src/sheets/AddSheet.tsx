// 自己加一站。只問一件事：一定要去，還是順路有空再去。
import { useState } from 'react';
import { DomyButton, DomyTextField } from '@domy/design';
import { Sheet } from '../components/Sheet';
import { addOwn } from '../domain/plan';
import { useApp } from '../store';

export function AddSheet({ onClose }: { onClose: () => void }) {
  const { act } = useApp();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | undefined>();
  const n = name.trim();
  const need = () => {
    if (n) return true;
    setError('先打店名或地方的名字。');
    return false;
  };
  return (
    <Sheet visible title="自己加一站" onClose={onClose}>
      <DomyTextField
        label="想去哪"
        placeholder="店名或地方"
        helper="這一版還不會幫你查它在哪，加進來之後地圖上不會有它。"
        error={error}
        maxLength={30}
        autoFocus
        value={name}
        onChangeText={(v) => {
          setName(v);
          setError(undefined);
        }}
      />
      <DomyButton
        title="一定要去，幫我排進去"
        fullWidth
        onPress={() => {
          if (!need()) return;
          act((d) => (d.trip ? addOwn(d.trip, d.seeds, n) : undefined), { undoable: true });
          onClose();
        }}
      />
      <DomyButton
        title="順路有空再去"
        variant="secondary"
        fullWidth
        onPress={() => {
          if (!need()) return;
          act(
            (d) => {
              d.pool.push(n);
              return `「${n}」放進順路可去，不排時間。`;
            },
            { undoable: true },
          );
          onClose();
        }}
      />
    </Sheet>
  );
}
