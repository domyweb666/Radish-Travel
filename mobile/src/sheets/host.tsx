// 彈出卡的總管：畫面只要說「打開哪一張」，同一時間只會有一張。
import { createContext, useContext, useMemo, useState, type ReactNode } from 'react';
import { AddSheet } from './AddSheet';
import { AlbumSheet, type AlbumSource } from './AlbumSheet';
import { ChatSheet } from './ChatSheet';
import { MapSheet } from './MapSheet';
import { MoreSheet } from './MoreSheet';
import { StopSheet } from './StopSheet';

export type SheetReq = { kind: 'stop'; id: string } | { kind: 'chat' } | { kind: 'map'; day: number } | { kind: 'add' } | { kind: 'more'; day: number } | { kind: 'album'; source: AlbumSource };

const SheetCtx = createContext<{ open: (r: SheetReq) => void; close: () => void } | null>(null);

export function SheetHost({ children }: { children: ReactNode }) {
  const [req, setReq] = useState<SheetReq | null>(null);
  const api = useMemo(() => ({ open: (r: SheetReq) => setReq(r), close: () => setReq(null) }), []);
  return (
    <SheetCtx.Provider value={api}>
      {children}
      {req?.kind === 'stop' ? <StopSheet id={req.id} onClose={api.close} /> : null}
      {req?.kind === 'chat' ? <ChatSheet onClose={api.close} /> : null}
      {req?.kind === 'map' ? <MapSheet day={req.day} onClose={api.close} /> : null}
      {req?.kind === 'album' ? <AlbumSheet source={req.source} onClose={api.close} onOpenStop={(id) => setReq({ kind: 'stop', id })} /> : null}
      {req?.kind === 'add' ? <AddSheet onClose={api.close} /> : null}
      {req?.kind === 'more' ? <MoreSheet day={req.day} onClose={api.close} onAdd={() => setReq({ kind: 'add' })} /> : null}
    </SheetCtx.Provider>
  );
}

export function useSheets() {
  const c = useContext(SheetCtx);
  if (!c) throw new Error('找不到 SheetHost');
  return c;
}
