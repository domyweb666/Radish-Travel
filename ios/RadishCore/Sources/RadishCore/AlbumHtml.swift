// 把一趟去過的站做成一頁網頁：上面是地圖，下面是每一天去了哪、寫的那一句、照片。
// 整頁是一個檔案，照片直接包在裡面，傳給朋友用瀏覽器就能開。純函式，不碰檔案。
// 這是給朋友看的網頁，不是 app 的畫面：它有自己的樣式，不受「不准寫死數值」檢查。
// 外部只載一樣東西：Leaflet（固定版本，附完整性雜湊，被竄改瀏覽器會拒絕執行）。
//
// 地圖有兩層：一定會有的是自己畫的路線圖（不用網路）；
// 朋友那邊有網路、而且地圖圖磚載得到時，會換成可以縮放的真地圖（Leaflet＋OpenStreetMap）。
// 照 mobile/album/albumHtml.ts 搬，樣板的字一字不改。
import Foundation

struct AlbumStop: Hashable, Sendable {
    var n: String
    var kr: String? = nil
    /// 第幾天
    var day: Int? = nil
    /// 那一天的日期，已經排好版的字
    var date: String? = nil
    var say: String? = nil
    var lat: Double? = nil
    var lng: Double? = nil
    /// 照片，已經轉成 data: 網址
    var photos: [String]
}

struct Album: Hashable, Sendable {
    var title: String
    var dates: String
    var stops: [AlbumStop]
}

/// TS 的 esc
private func albumEsc(_ s: String) -> String {
    var o: String = s.replacingOccurrences(of: "&", with: "&amp;")
    o = o.replacingOccurrences(of: "<", with: "&lt;")
    o = o.replacingOccurrences(of: ">", with: "&gt;")
    o = o.replacingOccurrences(of: "\"", with: "&quot;")
    o = o.replacingOccurrences(of: "'", with: "&#39;")
    return o
}

/// JSON.stringify 對字串的寫法：雙引號、反斜線、控制字元要跳脫
private func albumJsonString(_ s: String) -> String {
    var o: String = "\""
    for u in s.unicodeScalars {
        switch u.value {
        case 0x22: o += "\\\""
        case 0x5C: o += "\\\\"
        case 0x08: o += "\\b"
        case 0x0C: o += "\\f"
        case 0x0A: o += "\\n"
        case 0x0D: o += "\\r"
        case 0x09: o += "\\t"
        default:
            if u.value < 0x20 {
                o += "\\u" + String(format: "%04x", Int(u.value))
            } else {
                o.unicodeScalars.append(u)
            }
        }
    }
    o += "\""
    return o
}

/// JSON.stringify 對數字的寫法（JavaScript 的 Number 轉字串）：整數不帶小數點，
/// 很小或很大的數才用科學記號。Swift 的寫法在這兩點不一樣，所以自己排。
private func albumJsonNumber(_ v: Double) -> String {
    if !v.isFinite { return "null" }
    if v == 0 { return "0" }
    let neg: Bool = v < 0
    let raw: String = "\(abs(v))"  // 能讀回原值的最短寫法，例如 37.5796、5.0、1e-05、1.5e+16
    var mant: String = raw
    var exp: Int = 0
    let parts: [String] = raw.lowercased().components(separatedBy: "e")
    if parts.count == 2 {
        mant = parts[0]
        exp = Int(parts[1].replacingOccurrences(of: "+", with: "")) ?? 0
    }
    let mp: [String] = mant.components(separatedBy: ".")
    let intPart: String = mp.first ?? "0"
    let fracPart: String = mp.count > 1 ? mp[1] : ""
    // 全部的有效數字（去掉前面的 0 和後面的 0），和小數點該在第幾位之後
    var digits: [Character] = Array(intPart + fracPart)
    var point: Int = intPart.count + exp
    while digits.count > 1, digits.first == "0" {
        digits.removeFirst()
        point -= 1
    }
    while digits.count > 1, digits.last == "0" {
        digits.removeLast()
    }
    let k: Int = digits.count
    var out: String = ""
    if point >= k && point <= 21 {
        out = String(digits) + String(repeating: "0", count: point - k)
    } else if point > 0 && point <= 21 {
        out = String(digits[0..<point]) + "." + String(digits[point..<k])
    } else if point > -6 && point <= 0 {
        out = "0." + String(repeating: "0", count: -point) + String(digits)
    } else {
        let e: Int = point - 1
        let head: String = String(digits[0..<1])
        let tail: String = k > 1 ? "." + String(digits[1..<k]) : ""
        out = head + tail + "e" + (e < 0 ? "-" : "+") + String(abs(e))
    }
    return (neg ? "-" : "") + out
}

/// toFixed(1)。跟 String(format: "%.1f") 只差在剛好卡在中間的數（例如 0.25）：JavaScript 往大的進位
private func albumFixed1(_ x: Double) -> String {
    let a: Double = abs(x)
    if a < 1e12 {
        let q: Double = a * 4
        if q == q.rounded(.down) {
            let m: Int = Int(q)
            if m % 2 != 0 {
                // a = m/4，小數是 .25 或 .75，乘十後剛好是 x.5
                let n: Int = (m * 10) / 4 + 1
                return (x < 0 ? "-" : "") + String(n / 10) + "." + String(n % 10)
            }
        }
    }
    return String(format: "%.1f", x)
}

/// 不用網路的路線圖：把經緯度攤平到一張 600×360 的圖上
func sketchSvg(_ stops: [AlbumStop]) -> String {
    var pts: [(i: Int, lat: Double, lng: Double)] = []
    for (i, s) in stops.enumerated() {
        if let lat = s.lat, let lng = s.lng {
            pts.append((i: i, lat: lat, lng: lng))
        }
    }
    if pts.isEmpty { return "" }
    let W: Double = 600
    let H: Double = 360
    let PAD: Double = 44
    let lats: [Double] = pts.map { (p: (i: Int, lat: Double, lng: Double)) -> Double in p.lat }
    let midLat: Double = ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2
    let kx: Double = cos((midLat * Double.pi) / 180)  // 經度在這個緯度上比較短
    let xs: [Double] = pts.map { (p: (i: Int, lat: Double, lng: Double)) -> Double in p.lng * kx }
    let ys: [Double] = pts.map { (p: (i: Int, lat: Double, lng: Double)) -> Double in -p.lat }
    let minX: Double = xs.min() ?? 0
    let minY: Double = ys.min() ?? 0
    let spanX: Double = max((xs.max() ?? 0) - minX, 1e-6)
    let spanY: Double = max((ys.max() ?? 0) - minY, 1e-6)
    let k: Double = min((W - PAD * 2) / spanX, (H - PAD * 2) / spanY)
    let ox: Double = (W - spanX * k) / 2
    let oy: Double = (H - spanY * k) / 2

    var lineParts: [String] = []
    var dots: String = ""
    for j in 0..<pts.count {
        let i: Int = pts[j].i
        let x: Double = ox + (xs[j] - minX) * k
        let y: Double = oy + (ys[j] - minY) * k
        let fx: String = albumFixed1(x)
        let fy: String = albumFixed1(y)
        lineParts.append((j > 0 ? "L" : "M") + fx + "," + fy)
        dots += #"<g class="pin" data-i="\#(i)"><circle cx="\#(fx)" cy="\#(fy)" r="15"/>"#
        dots += #"<text x="\#(fx)" y="\#(albumFixed1(y + 5))">\#(i + 1)</text></g>"#
    }
    let line: String = lineParts.joined(separator: " ")
    return #"<svg viewBox="0 0 600 360" role="img" aria-label="這趟走過的路線"><path class="route" d="\#(line)"/>\#(dots)</svg>"#
}

func albumHtml(_ a: Album) -> String {
    var located: Int = 0
    var photos: Int = 0
    for s in a.stops {
        if s.lat != nil && s.lng != nil { located += 1 }
        photos += s.photos.count
    }

    var lastDay: Int? = nil
    var cardList: [String] = []
    for (i, s) in a.stops.enumerated() {
        var head: String = ""
        if let day = s.day, day != lastDay {
            var span: String = ""
            if let date = s.date, !date.isEmpty {
                span = "<span>" + albumEsc(date) + "</span>"
            }
            head = "<h2>第 \(day) 天" + span + "</h2>"
        }
        lastDay = s.day ?? lastDay

        var pics: String = ""
        if !s.photos.isEmpty {
            var imgs: String = ""
            for p in s.photos {
                imgs += #"<img src="\#(p)" alt="\#(albumEsc(s.n))的照片" loading="lazy">"#
            }
            pics = #"<div class="pics n\#(min(s.photos.count, 3))">"# + imgs + "</div>"
        }

        var kr: String = ""
        if let v = s.kr, !v.isEmpty {
            kr = #"<p class="kr">"# + albumEsc(v) + "</p>"
        }
        var say: String = ""
        if let v = s.say, !v.isEmpty {
            say = #"<p class="say">"# + albumEsc(v) + "</p>"
        }

        var card: String = head
        card += #"<article id="s\#(i)" data-i="\#(i)"><div class="num">\#(i + 1)</div>"#
        card += #"<div class="body"><h3>"# + albumEsc(s.n) + "</h3>"
        card += kr + say + pics + "</div></article>"
        cardList.append(card)
    }
    let cards: String = cardList.joined(separator: "\n")

    // 要塞進 <script> 的 JSON：把 < 換掉，內容裡的 </script> 才不會把頁面弄壞
    var pointList: [String] = []
    for (i, s) in a.stops.enumerated() {
        guard let lat = s.lat, let lng = s.lng else { continue }
        var pic: String = "null"
        if let first = s.photos.first {
            pic = albumJsonString(first)
        }
        var one: String = "{\"i\":" + String(i)
        one += ",\"n\":" + albumJsonString(s.n)
        one += ",\"lat\":" + albumJsonNumber(lat)
        one += ",\"lng\":" + albumJsonNumber(lng)
        one += ",\"pic\":" + pic + "}"
        pointList.append(one)
    }
    let pointsRaw: String = "[" + pointList.joined(separator: ",") + "]"
    let points: String = pointsRaw.replacingOccurrences(of: "<", with: "\\u003c")

    let title: String = albumEsc(a.title)
    var sub: String = albumEsc(a.dates) + "・去了 \(a.stops.count) 個地方"
    if photos > 0 {
        sub += "・\(photos) 張照片"
    }

    var mapBlock: String = ""
    if located > 0 {
        var missing: String = ""
        if located < a.stops.count {
            missing = "有 \(a.stops.count - located) 站沒有位置資料，不在地圖上。"
        }
        mapBlock = #"<div class="mapbox" id="mapbox"><div id="sketch">"# + sketchSvg(a.stops)
        mapBlock += #"</div><div id="map"></div></div><p class="mapnote">點地圖上的數字，會跳到那一站。"#
        mapBlock += missing + "</p>"
    }

    // 下面這一大段是原樣的網頁樣板。#"""…"""# 裡的反斜線和引號都是字面上的字，只有 \#( ) 會被換成值。
    // 結尾的 """# 貼齊最左邊，所以每一行前面的空白都會原樣留著。
    return #"""
<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>\#(title)</title>
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
<h1>\#(title)</h1>
<p>\#(sub)</p>
</header>
\#(mapBlock)
\#(cards)
<footer>用「蘿蔔旅行」做的。</footer>
</div>
<div id="big"><img alt=""></div>
<script>
var PTS=\#(points);
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

"""#
}
