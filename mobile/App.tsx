// 蘿蔔旅行：四個分頁（這趟／行前／旅行／我），用 Domy Design 的懸浮分頁列。
import { useState } from 'react';
import { View } from 'react-native';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { DomyTabBar, DomyThemeProvider, useDomy } from '@domy/design';
import { TabMe, TabPrep, TabTrip, TabTrips } from './src/components/icons';
import { NoticeBar } from './src/components/NoticeBar';
import { MeScreen } from './src/screens/MeScreen';
import { PrepScreen } from './src/screens/PrepScreen';
import { TripScreen } from './src/screens/TripScreen';
import { TripsScreen } from './src/screens/TripsScreen';
import { SheetHost } from './src/sheets/host';
import { AppProvider, useApp } from './src/store';
import { radishTheme } from './src/theme';

const TABS = [
  { key: 'trip', title: '這趟', Icon: TabTrip },
  { key: 'prep', title: '行前', Icon: TabPrep },
  { key: 'trips', title: '旅行', Icon: TabTrips },
  { key: 'me', title: '我', Icon: TabMe },
] as const;
type TabKey = (typeof TABS)[number]['key'];

export default function App() {
  return (
    <SafeAreaProvider>
      <DomyThemeProvider theme={radishTheme}>
        <AppProvider>
          <SheetHost>
            <Shell />
          </SheetHost>
        </AppProvider>
      </DomyThemeProvider>
    </SafeAreaProvider>
  );
}

function Shell() {
  const { c, scheme } = useDomy();
  const { ready } = useApp();
  const [tab, setTab] = useState<TabKey>('trip');
  const index = TABS.findIndex((t) => t.key === tab);

  // 沒用導覽套件，照 DomyTabBar 要的形狀自己給
  const state = { index, routes: TABS.map((t) => ({ key: t.key, name: t.key })) };
  const descriptors = Object.fromEntries(
    TABS.map((t) => [t.key, { options: { title: t.title, tabBarIcon: ({ color }: { color: string }) => <t.Icon color={color} /> } }]),
  );
  const navigation = {
    emit: () => ({ defaultPrevented: false }),
    navigate: (name: string) => setTab(name as TabKey),
  };

  return (
    <View style={{ flex: 1, backgroundColor: c.canvas }}>
      <StatusBar style={scheme === 'dark' ? 'light' : 'dark'} />
      {ready ? (
        <>
          {tab === 'trip' && <TripScreen goSettings={() => setTab('me')} goPrep={() => setTab('prep')} />}
          {tab === 'prep' && <PrepScreen goTrip={() => setTab('trip')} />}
          {tab === 'trips' && <TripsScreen goTrip={() => setTab('trip')} />}
          {tab === 'me' && <MeScreen />}
          <NoticeBar />
          <DomyTabBar state={state} descriptors={descriptors} navigation={navigation} />
        </>
      ) : null}
    </View>
  );
}
