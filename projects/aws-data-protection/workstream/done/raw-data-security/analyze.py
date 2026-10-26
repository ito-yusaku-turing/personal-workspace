"""cw.json からバケットごとの容量・最終増加日・アクセスの痕跡を TSV にする。"""
import json
import sys
from datetime import date, timedelta

data = json.load(open(sys.argv[1]))
TODAY = date.today()
TB = 1e12
FA = "IntelligentTieringFAStorage"
COLD = ("IntelligentTieringIAStorage", "IntelligentTieringAIAStorage",
        "IntelligentTieringAAStorage", "IntelligentTieringDAAStorage")


def last(s):
    return s[-1][1] if s else 0.0


def at(s, d):
    """d 以前で最も新しい値。"""
    v = None
    for ds, x in s:
        if ds <= d.isoformat():
            v = x
    return v


rows = []
for r in data:
    sizes = r.get("sizes", {})
    objs = r.get("objects", [])
    total = sum(last(s) for s in sizes.values())
    by_class = {k: last(s) for k, s in sizes.items() if last(s) > 0}

    # 最後にオブジェクト数が増えた日
    last_inc = None
    for (d0, a), (d1, b) in zip(objs, objs[1:]):
        if b > a:
            last_inc = d1
    o_now = last(objs)
    o_6m = at(objs, TODAY - timedelta(days=182))
    o_12m = at(objs, TODAY - timedelta(days=365))

    # IT の再アクセス: 低頻度層が減り、同じ日に高頻度層が増え、オブジェクト数は増えていない
    last_reaccess = None
    reaccess_days_12m = 0
    fa = dict(sizes.get(FA, []))
    cold = {}
    for k in COLD:
        for ds, v in sizes.get(k, []):
            cold[ds] = cold.get(ds, 0) + v
    on = dict(objs)
    days = sorted(set(fa) & set(cold))
    for d0, d1 in zip(days, days[1:]):
        dcold = cold[d1] - cold[d0]
        dfa = fa[d1] - fa[d0]
        grew = on.get(d1, 0) > on.get(d0, 0)
        if dcold < -1e9 and dfa > 0.5 * -dcold and not grew:
            last_reaccess = d1
            if d1 >= (TODAY - timedelta(days=365)).isoformat():
                reaccess_days_12m += 1

    reqs = {}
    for fid, ms in r.get("requests", {}).items():
        for m, s in ms.items():
            reqs.setdefault(m, {"6m": 0, "12m": 0, "last": None})
            for ds, v in s:
                if v > 0:
                    if ds >= (TODAY - timedelta(days=182)).isoformat():
                        reqs[m]["6m"] += v
                    if ds >= (TODAY - timedelta(days=365)).isoformat():
                        reqs[m]["12m"] += v
                    if not reqs[m]["last"] or ds > reqs[m]["last"]:
                        reqs[m]["last"] = ds
        break  # FilterId はバケット全体（最初のもの）だけ使う

    rows.append({
        "bucket": r["bucket"], "region": r["region"], "tb": total / TB,
        "objects": o_now, "obj_6m": o_6m, "obj_12m": o_12m, "last_inc": last_inc,
        "last_reaccess": last_reaccess, "reaccess_days_12m": reaccess_days_12m,
        "it_fa_tb": by_class.get(FA, 0) / TB,
        "it_cold_tb": sum(by_class.get(k, 0) for k in COLD) / TB,
        "classes": {k.replace("Storage", ""): round(v / TB, 2) for k, v in by_class.items()},
        "reqs": reqs, "filters": list(r.get("requests", {})),
    })

rows.sort(key=lambda x: -x["tb"])
json.dump(rows, open(sys.argv[2], "w"), indent=1, default=str)
for x in rows:
    if x["tb"] < 0.5:
        continue
    print(f'{x["bucket"][:48]:48} {x["tb"]:9.1f}TB  inc={x["last_inc"]}  reacc={x["last_reaccess"]}({x["reaccess_days_12m"]})  '
          f'FA={x["it_fa_tb"]:.0f} cold={x["it_cold_tb"]:.0f}  {x["classes"]}  '
          + (" GET6m={:.0f} GET12m={:.0f} lastGET={}".format(x["reqs"]["GetRequests"]["6m"], x["reqs"]["GetRequests"]["12m"], x["reqs"]["GetRequests"]["last"]) if "GetRequests" in x["reqs"] else ""))
print("small(<0.5TB):", sum(1 for x in rows if x["tb"] < 0.5))
