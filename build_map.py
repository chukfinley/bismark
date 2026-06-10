import json, time, httpx
from markets import MARKETS, address

H={"User-Agent":"bismark-market-map/1.0 (claude@chuk.dev)"}
def geocode(q):
    for params in [{"street":m['street'],"city":m['city'],"postalcode":m['plz'],"country":"Germany","format":"json","limit":1},
                   {"q":q+", Germany","format":"json","limit":1}]:
        try:
            r=httpx.get("https://nominatim.openstreetmap.org/search",params=params,headers=H,timeout=20)
            j=r.json()
            if j: return float(j[0]["lat"]),float(j[0]["lon"])
        except Exception as e:
            pass
        time.sleep(1.1)
    return None,None

out=[]
for m in MARKETS:
    q=address(m)
    m=dict(m); m['street']=m['street']  # copy
    lat,lon=geocode(q)
    rec={**m,"address":q,"lat":lat,"lon":lon}
    out.append(rec)
    print(f"{'OK ' if lat else 'MISS'} {m['retailer']:5} {q}  -> {lat},{lon}")
    time.sleep(1.0)

json.dump(out,open("markets.json","w"),ensure_ascii=False,indent=2)
print("wrote markets.json", len(out))

# Leaflet map
colors={"REWE":"#cc0000","EDEKA":"#005ca9","ALDI":"#00457c"}
pts=[r for r in out if r["lat"]]
clat=sum(r["lat"] for r in pts)/len(pts); clon=sum(r["lon"] for r in pts)/len(pts)
markers="\n".join(
  f"""L.marker([{r['lat']},{r['lon']}],{{icon:ic('{colors.get(r['retailer'],'#444')}')}}).addTo(map)
     .bindPopup('<b>{r['name']}</b><br>{r['address']}<br><small>{r['retailer']}{' · ID '+r['ident'] if r['ident'] else ''}</small>');"""
  for r in pts)
html=f"""<!doctype html><html><head><meta charset=utf-8><title>Märkte Umkreis Kiel</title>
<meta name=viewport content="width=device-width,initial-scale=1">
<link rel=stylesheet href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css">
<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
<style>html,body,#map{{height:100%;margin:0}}.legend{{position:absolute;z-index:1000;right:10px;top:10px;background:#fff;padding:8px 12px;border-radius:8px;font:13px sans-serif;box-shadow:0 1px 6px rgba(0,0,0,.3)}}.legend i{{display:inline-block;width:12px;height:12px;border-radius:50%;margin-right:6px;vertical-align:middle}}</style>
</head><body>
<div class=legend>
<div><i style="background:#cc0000"></i>REWE</div>
<div><i style="background:#005ca9"></i>EDEKA</div>
<div><i style="background:#00457c"></i>ALDI</div>
</div>
<div id=map></div>
<script>
var map=L.map('map').setView([{clat},{clon}],11);
L.tileLayer('https://{{s}}.tile.openstreetmap.org/{{z}}/{{x}}/{{y}}.png',{{attribution:'© OpenStreetMap'}}).addTo(map);
function ic(c){{return L.divIcon({{className:'',html:'<div style=\"background:'+c+';width:18px;height:18px;border:2px solid #fff;border-radius:50%;box-shadow:0 0 3px #000\"></div>',iconSize:[18,18],iconAnchor:[9,9]}});}}
{markers}
</script></body></html>"""
open("markets_map.html","w").write(html)
print("wrote markets_map.html")
