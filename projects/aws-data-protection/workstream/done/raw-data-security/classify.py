import json
from datetime import date, timedelta
T=date.today(); d6=(T-timedelta(days=182)).isoformat(); d12=(T-timedelta(days=365)).isoformat()
FA="IntelligentTieringFAStorage"; COLD=("IntelligentTieringIAStorage","IntelligentTieringAIAStorage","IntelligentTieringAAStorage","IntelligentTieringDAAStorage")
out=[]
for r in json.load(open("cw.json")):
    s=r.get("sizes",{}); on=dict(r.get("objects",[]))
    tb=sum(v[-1][1] for v in s.values() if v)/1e12
    o=r.get("objects",[])
    last_inc=None
    for (a,x),(b,y) in zip(o,o[1:]):
        if y>x: last_inc=b
    fa=dict(s.get(FA,[])); cold={}
    for k in COLD:
        for d,v in s.get(k,[]): cold[d]=cold.get(d,0)+v
    it = bool(fa or cold)
    last_re=None; re12=0
    days=sorted(set(fa)&set(cold))
    for a,b in zip(days,days[1:]):
        dc=cold[b]-cold[a]; df=fa[b]-fa[a]
        if dc<-1e10 and df>0.5*-dc and not on.get(b,0)>on.get(a,0):
            last_re=b
            if b>=d12: re12+=df/1e12
    lastget=None; get12=None
    for fid,ms in r.get("requests",{}).items():
        g=[(d,v) for d,v in ms.get("GetRequests",[]) if v>0]
        if g: lastget=g[-1][0]; get12=sum(v for d,v in g if d>=d12)
        break
    last_any=max([x for x in (last_inc,last_re,lastget) if x], default=None)
    cls = "A:6か月以内" if last_any and last_any>=d6 else "B:6〜12か月" if last_any and last_any>=d12 else "C:1年以上"
    # 現存データの低頻度層の割合
    cur_fa = fa[max(fa)]/1e12 if fa else 0; cur_cold = cold[max(cold)]/1e12 if cold else 0
    out.append(dict(bucket=r["bucket"],tb=round(tb,2),objects=o[-1][1] if o else 0,last_put=last_inc,last_reaccess=last_re,reaccess_tb_12m=round(re12,1),
        last_get=lastget,get_req_12m=get12,it=it,fa_tb=round(cur_fa,1),cold_tb=round(cur_cold,1),class_=cls,
        signal="IT+req" if lastget and it else "req" if lastget else "IT" if it else "PUTのみ"))
out.sort(key=lambda x:-x["tb"])
json.dump(out,open("classified.json","w"),indent=1)
with open("classified.tsv","w") as f:
    keys=list(out[0])
    f.write("\t".join(keys)+"\n")
    for x in out: f.write("\t".join(str(x[k]) for k in keys)+"\n")
from collections import defaultdict
agg=defaultdict(lambda:[0,0.0])
for x in out: agg[x["class_"]][0]+=1; agg[x["class_"]][1]+=x["tb"]
print(dict(agg))
for x in out:
    if x["tb"]>=0.5 or x["class_"]!="A:6か月以内":
        if x["tb"]>=0.1: print(f'{x["class_"]:10} {x["bucket"][:46]:46} {x["tb"]:8.1f}  PUT={x["last_put"]}  再ｱｸｾｽ={x["last_reaccess"]}({x["reaccess_tb_12m"]}TB)  GET={x["last_get"]}  FA/cold={x["fa_tb"]}/{x["cold_tb"]}  [{x["signal"]}]')
print("C/B で 0.1TB 未満:", sum(1 for x in out if x["class_"]!="A:6か月以内" and x["tb"]<0.1))
