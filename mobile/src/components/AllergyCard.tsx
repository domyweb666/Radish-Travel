// 過敏告知卡：一段韓文，點餐前拿給店員看。沒網路也能用。
// app 沒有每家店的食材資料，所以做不到幫你排除，只能幫你把話講清楚。
import * as Clipboard from 'expo-clipboard';
import { useState } from 'react';
import { DomyButton, DomyText } from '@domy/design';
import { allergyCard } from '../domain/prefs';
import { Card, Label } from './ui';

export function AllergyCard({ list }: { list: string[] }) {
  const [copied, setCopied] = useState(false);
  const card = allergyCard(list);
  if (!card) return null;
  return (
    <Card>
      <Label>給店員看（韓文）</Label>
      <DomyText variant="title2" accessibilityLabel={`韓文告知卡。中文意思：${card.zh}`}>
        {card.kr}
      </DomyText>
      <Label>中文意思</Label>
      <DomyText variant="body">{card.zh}</DomyText>
      <DomyButton
        title={copied ? '複製了' : '複製韓文'}
        variant="secondary"
        size="compact"
        style={{ alignSelf: 'flex-start' }}
        onPress={() => {
          Clipboard.setStringAsync(card.kr).then(() => setCopied(true)).catch(() => {});
        }}
      />
      <DomyText variant="footnote" tone="secondary">
        未核對：這段韓文是照常見說法寫的，還沒請懂韓文的人看過。過敏嚴重的話，出發前請找懂韓文的人確認，或帶醫師開的說明。
      </DomyText>
    </Card>
  );
}
