// 把一趟去過的站做成一頁網頁：上面是地圖，下面是每一天去了哪、寫的那一句、照片。
// 整頁是一個檔案，照片直接包在裡面，傳給朋友用瀏覽器就能開。純函式，不碰檔案。
// 這是給朋友看的網頁，不是 app 的畫面，所以放在 src 外面：它有自己的樣式，不受「不准寫死數值」檢查。
// 外部只載一樣東西：Leaflet（固定版本，附完整性雜湊，被竄改瀏覽器會拒絕執行）。
//
// 地圖有兩層：一定會有的是自己畫的路線圖（不用網路）；
// 朋友那邊有網路、而且地圖圖磚載得到時，會換成可以縮放的真地圖（Leaflet＋OpenStreetMap）。

export interface AlbumStop {
  n: string;
  kr?: string;
  /** 第幾天 */
  day?: number;
  /** 那一天的日期，已經排好版的字 */
  date?: string;
  say?: string;
  lat?: number | null;
  lng?: number | null;
  /** 照片，已經轉成 data: 網址 */
  photos: string[];
}
export interface Album {
  title: string;
  dates: string;
  stops: AlbumStop[];
}

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
/** 要塞進 <script> 的 JSON：把 < 換掉，內容裡的 </script> 才不會把頁面弄壞 */
const json = (v: unknown) => JSON.stringify(v).replace(/</g, '\\u003c');

/** 不用網路的路線圖：把經緯度攤平到一張 600×360 的圖上 */
export function sketchSvg(stops: AlbumStop[]): string {
  const pts = stops.map((s, i) => ({ i, lat: s.lat, lng: s.lng })).filter((p): p is { i: number; lat: number; lng: number } => typeof p.lat === 'number' && typeof p.lng === 'number');
  if (!pts.length) return '';
  const W = 600, H = 360, PAD = 44;
  const lats = pts.map((p) => p.lat), lngs = pts.map((p) => p.lng);
  const midLat = (Math.min(...lats) + Math.max(...lats)) / 2;
  const kx = Math.cos((midLat * Math.PI) / 180); // 經度在這個緯度上比較短
  const xs = pts.map((p) => p.lng * kx), ys = pts.map((p) => -p.lat);
  const minX = Math.min(...xs), minY = Math.min(...ys);
  const spanX = Math.max(Math.max(...xs) - minX, 1e-6), spanY = Math.max(Math.max(...ys) - minY, 1e-6);
  const k = Math.min((W - PAD * 2) / spanX, (H - PAD * 2) / spanY);
  const ox = (W - spanX * k) / 2, oy = (H - spanY * k) / 2;
  const xy = pts.map((p, j) => ({ i: p.i, x: ox + (xs[j] - minX) * k, y: oy + (ys[j] - minY) * k }));
  const line = xy.map((p, j) => `${j ? 'L' : 'M'}${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' ');
  const dots = xy
    .map((p) => `<g class="pin" data-i="${p.i}"><circle cx="${p.x.toFixed(1)}" cy="${p.y.toFixed(1)}" r="15"/><text x="${p.x.toFixed(1)}" y="${(p.y + 5).toFixed(1)}">${p.i + 1}</text></g>`)
    .join('');
  return `<svg viewBox="0 0 ${W} ${H}" role="img" aria-label="這趟走過的路線"><path class="route" d="${line}"/>${dots}</svg>`;
}

export function albumHtml(a: Album): string {
  const located = a.stops.filter((s) => typeof s.lat === 'number' && typeof s.lng === 'number').length;
  const photos = a.stops.reduce((n, s) => n + s.photos.length, 0);
  let lastDay: number | undefined;
  const cards = a.stops
    .map((s, i) => {
      const head = s.day != null && s.day !== lastDay ? `<h2>第 ${s.day} 天${s.date ? `<span>${esc(s.date)}</span>` : ''}</h2>` : '';
      lastDay = s.day ?? lastDay;
      const pics = s.photos.length ? `<div class="pics n${Math.min(s.photos.length, 3)}">${s.photos.map((p) => `<img src="${p}" alt="${esc(s.n)}的照片" loading="lazy">`).join('')}</div>` : '';
      return `${head}<article id="s${i}" data-i="${i}"><div class="num">${i + 1}</div><div class="body"><h3>${esc(s.n)}</h3>${s.kr ? `<p class="kr">${esc(s.kr)}</p>` : ''}${s.say ? `<p class="say">${esc(s.say)}</p>` : ''}${pics}</div></article>`;
    })
    .join('\n');
  const points = a.stops.map((s, i) => ({ i, n: s.n, lat: s.lat ?? null, lng: s.lng ?? null, pic: s.photos[0] ?? null })).filter((p) => p.lat != null && p.lng != null);

  return `<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(a.title)}</title>
<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" integrity="sha256-p4NxAoJBhIIN+hmNHrzRCf9tD/miZyoHS5obTRR9BMY=" crossorigin="">
<style>
:root{--bg:#F7F3EC;--card:#fff;--ink:#2B2329;--muted:#75695f;--line:#E8DFD2;--accent:#B5501B;--soft:#F8E2D2}
@media (prefers-color-scheme:dark){:root{--bg:#1c1814;--card:#2a241e;--ink:#f3ede6;--muted:#b3a698;--line:#3d342b;--accent:#F0A064;--soft:#40281A}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:"PingFang TC","Noto Sans TC","Microsoft JhengHei",system-ui,sans-serif;line-height:1.6;-webkit-font-smoothing:antialiased}
.wrap{max-width:720px;margin:0 auto;padding:28px 16px 56px}
header{padding:8px 4px 20px}
h1{font-size:34px;line-height:1.2;margin:0 0 6px;font-weight:900;letter-spacing:.01em}
header p{margin:0;color:var(--muted);font-size:15px}
.mapbox{position:relative;border-radius:20px;overflow:hidden;background:var(--soft);border:1px solid var(--line);aspect-ratio:5/3}
#map{position:absolute;inset:0;visibility:hidden}
.mapbox.live #map{visibility:visible}
.mapbox.live #sketch{display:none}
#sketch{position:absolute;inset:0}
#sketch svg{width:100%;height:100%;display:block}
.route{fill:none;stroke:var(--accent);stroke-width:3;stroke-dasharray:2 9;stroke-linecap:round;stroke-linejoin:round}
.pin{cursor:pointer}
.pin circle{fill:var(--accent);stroke:var(--bg);stroke-width:3}
.pin text{fill:#fff;font-size:14px;font-weight:700;text-anchor:middle;font-family:system-ui,sans-serif}
.mapnote{font-size:12.5px;color:var(--muted);margin:8px 4px 0}
h2{font-size:15px;margin:30px 4px 10px;color:var(--accent);letter-spacing:.06em;font-weight:700}
h2 span{color:var(--muted);font-weight:400;margin-left:10px;letter-spacing:0}
article{display:flex;gap:12px;background:var(--card);border-radius:18px;padding:16px;margin:0 0 10px;scroll-margin-top:12px;border:1px solid transparent;transition:border-color .2s}
article.on{border-color:var(--accent)}
.num{flex:none;width:30px;height:30px;border-radius:50%;background:var(--accent);color:#fff;font-weight:700;font-size:14px;display:flex;align-items:center;justify-content:center;font-family:system-ui,sans-serif}
.body{flex:1;min-width:0}
h3{font-size:19px;margin:1px 0 0;font-weight:700}
.kr{margin:0;color:var(--muted);font-size:14px}
.say{margin:10px 0 0;font-size:16px;padding-left:12px;border-left:3px solid var(--soft)}
.pics{display:grid;gap:6px;margin-top:12px}
.pics.n1{grid-template-columns:1fr}.pics.n2{grid-template-columns:1fr 1fr}.pics.n3{grid-template-columns:1fr 1fr 1fr}
.pics img{width:100%;aspect-ratio:1;object-fit:cover;border-radius:12px;display:block;cursor:zoom-in;background:var(--soft)}
.pics.n1 img{aspect-ratio:4/3}
footer{margin:36px 4px 0;color:var(--muted);font-size:13px}
.mk{background:var(--accent);color:#fff;border:3px solid #fff;border-radius:50%;width:30px;height:30px;display:flex;align-items:center;justify-content:center;font:700 13px system-ui,sans-serif;box-shadow:0 2px 6px rgba(0,0,0,.3)}
.pop{font:14px/1.4 system-ui,sans-serif;min-width:120px}.pop b{display:block;margin-bottom:6px}.pop img{width:160px;height:120px;object-fit:cover;border-radius:8px;display:block}
#big{position:fixed;inset:0;background:rgba(0,0,0,.88);display:none;align-items:center;justify-content:center;z-index:9999;cursor:zoom-out}
#big.on{display:flex}#big img{max-width:96vw;max-height:92vh;border-radius:8px}
</style>
</head>
<body>
<div class="wrap">
<header>
<h1>${esc(a.title)}</h1>
<p>${esc(a.dates)}・去了 ${a.stops.length} 個地方${photos ? `・${photos} 張照片` : ''}</p>
</header>
${located ? `<div class="mapbox" id="mapbox"><div id="sketch">${sketchSvg(a.stops)}</div><div id="map"></div></div><p class="mapnote">點地圖上的數字，會跳到那一站。${located < a.stops.length ? `有 ${a.stops.length - located} 站沒有位置資料，不在地圖上。` : ''}</p>` : ''}
${cards}
<footer>用「蘿蔔旅行」做的。</footer>
</div>
<div id="big"><img alt=""></div>
<script>
var PTS=${json(points)};
function go(i){var el=document.getElementById('s'+i);if(!el)return;document.querySelectorAll('article.on').forEach(function(x){x.classList.remove('on')});el.classList.add('on');el.scrollIntoView({behavior:'smooth',block:'center'});}
document.querySelectorAll('.pin').forEach(function(p){p.addEventListener('click',function(){go(p.getAttribute('data-i'))})});
var big=document.getElementById('big');
document.querySelectorAll('.pics img').forEach(function(im){im.addEventListener('click',function(){big.firstChild.src=im.src;big.classList.add('on')})});
big.addEventListener('click',function(){big.classList.remove('on')});
function live(){
  if(!window.L||!PTS.length)return;
  var box=document.getElementById('mapbox');
  var map=L.map('map',{scrollWheelZoom:false});
  var tiles=L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png',{maxZoom:19,attribution:'&copy; OpenStreetMap contributors'});
  var ll=PTS.map(function(p){return [p.lat,p.lng]});
  function fit(){map.invalidateSize();map.fitBounds(ll,{padding:[36,36],maxZoom:15});}
  tiles.once('tileload',function(){box.classList.add('live');fit();});
  tiles.addTo(map);
  window.addEventListener('resize',fit);
  L.polyline(ll,{className:'route'}).addTo(map);
  PTS.forEach(function(p){
    var m=L.marker([p.lat,p.lng],{icon:L.divIcon({className:'',html:'<div class="mk">'+(p.i+1)+'</div>',iconSize:[30,30],iconAnchor:[15,15]})}).addTo(map);
    var d=document.createElement('div');d.className='pop';var b=document.createElement('b');b.textContent=p.n;d.appendChild(b);
    if(p.pic){var im=document.createElement('img');im.src=p.pic;d.appendChild(im);}
    m.bindPopup(d);m.on('click',function(){go(p.i)});
  });
  fit();
}
</script>
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js" integrity="sha256-20nQCchB9co0qIjJZRGuk2/Z9VM+kNiyxNV1lvTlZBo=" crossorigin="" onload="live()" async></script>
</body>
</html>
`;
}
