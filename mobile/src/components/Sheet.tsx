// 彈出卡：iOS 上是系統的頁面卡片，可以往下拉關掉；右上角一直有「關閉」。
import type { ReactNode } from 'react';
import { KeyboardAvoidingView, Modal, Platform, ScrollView, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { DomyIconButton, DomyText, T, useDomy } from '@domy/design';

export function Sheet({
  visible,
  title,
  onClose,
  scroll = true,
  children,
}: {
  visible: boolean;
  title: string;
  onClose: () => void;
  scroll?: boolean;
  children: ReactNode;
}) {
  const { c } = useDomy();
  const insets = useSafeAreaInsets();
  const bottom = insets.bottom + T.space[6];
  return (
    <Modal visible={visible} animationType="slide" presentationStyle="pageSheet" onRequestClose={onClose}>
      <KeyboardAvoidingView behavior={Platform.OS === 'ios' ? 'padding' : undefined} style={{ flex: 1, backgroundColor: c.canvas }}>
        <View
          style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: T.space[3],
            paddingHorizontal: T.size.screenMargin,
            paddingTop: T.space[5],
            paddingBottom: T.space[3],
          }}
        >
          <DomyText variant="title2" accessibilityRole="header" style={{ flex: 1 }} numberOfLines={2}>
            {title}
          </DomyText>
          <DomyIconButton title="關閉" label="關閉" tone="neutral" onPress={onClose} />
        </View>
        {scroll ? (
          <ScrollView
            keyboardShouldPersistTaps="handled"
            contentContainerStyle={{ paddingHorizontal: T.size.screenMargin, paddingBottom: bottom, gap: T.space[4] }}
          >
            {children}
          </ScrollView>
        ) : (
          <View style={{ flex: 1, paddingHorizontal: T.size.screenMargin, paddingBottom: bottom, gap: T.space[3] }}>{children}</View>
        )}
      </KeyboardAvoidingView>
    </Modal>
  );
}
