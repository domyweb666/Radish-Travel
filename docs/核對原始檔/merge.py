# 只合併過一次（2026-11-25）。之後的修正都直接改 seoul-checked.json，再跑會把修正蓋掉，所以擋住。
import sys
if '--force' not in sys.argv: sys.exit('再跑會蓋掉 seoul-checked.json 後來的修正；真的要跑加 --force')
import json,io,sys
D=r"C:/Users/fcharlie/AppData/Local/Temp/claude/76cd8714ebb655cf/ac3b4a6c-d6a7-4ec6-9978-9d9d3c906136/scratchpad/facts/"
R=r"E:/蘿蔔旅行/ios/RadishCore/Sources/RadishCore/Resources/"
L=lambda p: json.load(io.open(p,encoding='utf-8'))
base={p['id']:p for p in L(R+'seoul.json')['places']}
out=L(R+'seoul-checked.json')
facts={};drop=[];add=[]
for n in '1234':
    d=L(D+'r%s.json'%n); facts.update(d['facts']); drop+=d['drop']; add+=d['add']
    if n=='1': out['holidays']=sorted(d['holidays']); out['lunar']=d['lunar']
v2=L(D+'v2.json'); facts.update(v2['facts']); add+=v2['add']
addby={a['place']['id']:a['place'] for a in add}
for v in (L(D+'v1.json'),v2):
    for f in v['fix']:
        path=f['field'].split('.'); tgt=facts.get(f['id'])
        if path[0]=='add': tgt=addby[f['id']]; path=path[1:]
        if path[0]=='place': tgt=addby[f['id']]; path=path[1:]
        for k in path[:-1]: tgt=tgt[int(k) if k.isdigit() else k]
        if f['should'] is None: tgt.pop(path[-1],None)
        else: tgt[path[-1]]=f['should']
# 女性專用的汗蒸幕不放，換成男女都能去的
for x in ('p13a','p13b'): facts.pop(x,None)
add=[a for a in add if a['place']['id'] not in('p13a','p13b')]
# 便宜的排前面，排行程同分取前面的
order={'p47c':0,'p47b':0,'p47a':1}
k47=[a for a in add if a['place']['id'].startswith('p47')]
k47.sort(key=lambda a:a['place'].get('fee') or 0)
add=[a for a in add if not a['place']['id'].startswith('p47')]+k47
for o in facts['p11'].get('off',[]): o['why']='官網公告 2027 年 1 到 3 月展望台限制使用，重開日期未公布'
# 樂天世界不是一定要先訂
p=dict(base['p27']); p.pop('b',None); p.pop('tip',None); drop.append('p27'); add.append({'after':'p27','place':p})
def strip(o):
    if isinstance(o,dict): return {k:strip(v) for k,v in o.items() if v is not None}
    if isinstance(o,list): return [strip(x) for x in o]
    return o
facts=strip(facts); add=strip(add)
for a in add: a['place'].setdefault('kr','')
key=lambda i:(int(''.join(c for c in i if c.isdigit())),i)
out['facts']={k:facts[k] for k in sorted(facts,key=key)}; out['drop']=sorted(set(drop),key=key); out['add']=add
io.open(R+'seoul-checked.json','w',encoding='utf-8',newline='\n').write(json.dumps(out,ensure_ascii=False,indent=1)+'\n')
ids=[i for i in base if i not in out['drop']]+[a['place']['id'] for a in add]
from collections import Counter
print(len(ids),len(set(ids)),'nofact',[i for i in ids if i not in facts],'orphan',[i for i in facts if i not in ids])
print(Counter(f['status'] for f in facts.values()),'kr空',[i for i in ids if not ({**base,**{a['place']['id']:a['place'] for a in add}}[i]['kr'])])
FK='status checked src closed closedNth closedOn shift off hours last price addr tip book gone'.split()
BK='how url opensDays opensMonths opensDay opensAt decideDays cancel foreigner'.split()
PK='id n kr a s c lat lng b fee tip l up f ic'.split()
for k,f in facts.items():
    b=[x for x in f if x not in FK]+[x for x in f.get('book',{}) if x not in BK]
    if b: print('extra',k,b)
    if 'book' in f and 'how' not in f['book']: print('nohow',k)
    for x in('status','checked','src'):
        if x not in f: print('miss',k,x)
    for o in f.get('closedOn',[]):
        if not(o in out['lunar'] or (o.replace('-','').isdigit())): print('closedOn',k,o)
for a in add:
    b=[x for x in a['place'] if x not in PK]
    if b: print('pextra',a['place']['id'],b)
print([(k,f['closed'],f.get('shift')) for k,f in facts.items() if f.get('closed')])
print([(k,f['off']) for k,f in facts.items() if f.get('off')])
print([(k,{x:f['book'].get(x) for x in BK[2:7] if x in f['book']}) for k,f in facts.items() if 'book' in f])
m={**base,**{a['place']['id']:a['place'] for a in add}}
print('b無book',[i for i in ids if m[i].get('b') and 'book' not in facts.get(i,{})],'book無b',[i for i in ids if not m[i].get('b') and 'book' in facts.get(i,{})])
