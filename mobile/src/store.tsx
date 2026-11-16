// 整個 App 的狀態：存在手機本機（AsyncStorage），沒網路也看得到全部。
// 會改到行程的動作都走 act()，每次留一份改之前的樣子，最多 20 步，可以復原。
import AsyncStorage from '@react-native-async-storage/async-storage';
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { phaseOf, todayISO, type Phase } from './domain/dates';
import { defaultSettings } from './domain/plan';
import type { AppState, Settings } from './domain/types';

const KEY = 'radish-travel-v1';
const UNDO_MAX = 20;
const NOTICE_MS = 8000; // domy-ignore: 提示停留時間，不是動畫

export const blankState = (): AppState => ({
  settings: defaultSettings(),
  trip: null,
  shelf: [],
  seeds: [],
  pool: [],
  checks: {},
  chat: [],
  baskets: [],
  settingsDirty: false,
  aiConsent: false,
  guideSeen: false,
  remind: false,
  debugDay: null,
});

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v));

export function hydrate(raw: string | null): AppState {
  if (!raw) return blankState();
  try {
    const o = JSON.parse(raw) as Partial<AppState>;
    if (!o || typeof o !== 'object' || !o.settings) return blankState();
    const b = blankState();
    const st = { ...b.settings, ...o.settings };
    // 舊資料：「這趟想怎樣」原本記在行程上、只能選一個，現在搬到設定、可以好幾個
    const old = (o.trip as { purpose?: Settings['purposes'][number] } | null | undefined)?.purpose;
    if (old && !o.settings.purposes) st.purposes = [old];
    return { ...b, ...o, settings: st };
  } catch {
    return blankState();
  }
}

type Snapshot = Pick<AppState, 'trip' | 'seeds' | 'pool' | 'baskets' | 'settingsDirty'>;
export interface Notice {
  id: number;
  text: string;
  canUndo: boolean;
}

interface Ctx {
  s: AppState;
  ready: boolean;
  today: string;
  phase: Phase | null;
  notice: Notice | null;
  /** 改狀態。fn 直接改 draft；回傳的字串會顯示在提示條。undoable 為 true 時這一步可以復原 */
  act: (fn: (draft: AppState) => string | void, opts?: { undoable?: boolean }) => void;
  setSettings: (patch: Partial<Settings>) => void;
  undo: () => void;
  canUndo: boolean;
  say: (text: string) => void;
  dismissNotice: () => void;
  replaceAll: (next: AppState) => void;
}

const AppCtx = createContext<Ctx | null>(null);

export function AppProvider({ children }: { children: ReactNode }) {
  const [s, setS] = useState<AppState>(blankState);
  const [ready, setReady] = useState(false);
  const [notice, setNotice] = useState<Notice | null>(null);
  const [undoLen, setUndoLen] = useState(0);
  const undoStack = useRef<Snapshot[]>([]);
  const noticeId = useRef(0);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const sRef = useRef(s);
  sRef.current = s;

  useEffect(() => {
    AsyncStorage.getItem(KEY)
      .then((raw) => setS(hydrate(raw)))
      .catch(() => {})
      .finally(() => setReady(true));
  }, []);

  useEffect(() => {
    if (!ready) return;
    AsyncStorage.setItem(KEY, JSON.stringify(s)).catch(() => {});
  }, [s, ready]);

  const show = useCallback((text: string, canUndo: boolean) => {
    if (timer.current) clearTimeout(timer.current);
    const id = ++noticeId.current;
    setNotice({ id, text, canUndo });
    timer.current = setTimeout(() => setNotice((n) => (n && n.id === id ? null : n)), NOTICE_MS);
  }, []);

  const act = useCallback<Ctx['act']>(
    (fn, opts) => {
      const prev = sRef.current;
      const draft = clone(prev);
      const msg = fn(draft);
      if (opts?.undoable) {
        const { trip, seeds, pool, baskets, settingsDirty } = prev;
        undoStack.current.push(clone({ trip, seeds, pool, baskets, settingsDirty }));
        if (undoStack.current.length > UNDO_MAX) undoStack.current.shift();
        setUndoLen(undoStack.current.length);
      }
      sRef.current = draft;
      setS(draft);
      if (msg) show(msg, !!opts?.undoable);
    },
    [show],
  );

  const undo = useCallback(() => {
    const snap = undoStack.current.pop();
    if (!snap) return;
    setUndoLen(undoStack.current.length);
    const next = { ...sRef.current, ...snap };
    sRef.current = next;
    setS(next);
    show('復原了上一步。', false);
  }, [show]);

  const setSettings = useCallback(
    (patch: Partial<Settings>) => act((d) => {
      d.settings = { ...d.settings, ...patch, tuned: true };
      if (d.trip) d.settingsDirty = true;
    }),
    [act],
  );

  const replaceAll = useCallback((next: AppState) => {
    undoStack.current = [];
    setUndoLen(0);
    sRef.current = next;
    setS(next);
  }, []);

  const today = todayISO();
  const phase = useMemo(() => (s.trip ? phaseOf(s.trip.start, s.trip.days, today, s.debugDay) : null), [s.trip, s.debugDay, today]);

  const value: Ctx = {
    s,
    ready,
    today,
    phase,
    notice,
    act,
    setSettings,
    undo,
    canUndo: undoLen > 0,
    say: (text) => show(text, false),
    dismissNotice: () => setNotice(null),
    replaceAll,
  };
  return <AppCtx.Provider value={value}>{children}</AppCtx.Provider>;
}

export function useApp(): Ctx {
  const c = useContext(AppCtx);
  if (!c) throw new Error('找不到 AppProvider');
  return c;
}
