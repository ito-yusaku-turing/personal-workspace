#!/usr/bin/env python3
"""CloudFormation のルートのスタックを一覧し、持ち主のリポジトリの候補を付けて TSV で出す。
  python3 -I cfn_stacks.py <取得日のフォルダ> <リポジトリのフォルダ>...
持ち主の候補: スタック名が引用符つき（'Name' / "Name"）で現れる、マウント済みのリポジトリ（HEAD）。
"""
import json, sys, glob, subprocess, os, csv, datetime as dt
base, repos = sys.argv[1], sys.argv[2:]
now = dt.datetime(2026, 10, 28, tzinfo=dt.timezone.utc)
stacks = []
for f in glob.glob(f"{base}/*/cloudformation/describe-stacks.json"):
    region = f.split("/")[-3]
    for s in json.load(open(f))["Stacks"]:
        s["_region"] = region
        stacks.append(s)
names = sorted({s["StackName"] for s in stacks if not s.get("ParentId")})
pats = "\n".join(q + n + q for n in names for q in ("'", '"'))
hits = {n: [] for n in names}
for repo in repos:
    r = subprocess.run(["git", "-C", repo, "grep", "-h", "-o", "-F", "-f", "-", "--", ".", ":!**/node_modules/**", ":!**/*.lock", ":!**/package-lock.json"],
                       input=pats, capture_output=True, text=True)
    for m in set(r.stdout.split()):
        n = m.strip("'\"")
        if n in hits: hits[n].append(os.path.basename(repo.rstrip("/")))
nres = {}
for f in glob.glob(f"{base}/*/cloudformation/resources/*.json"):
    nres[(f.split("/")[-4], os.path.basename(f)[:-5])] = json.load(open(f))["StackResourceSummaries"]
w = csv.writer(sys.stdout, delimiter="\t")
w.writerow(["region", "stack", "status", "created", "updated", "idle_days", "n_resources", "types_top", "cdk", "repos", "termination_protect", "drift", "description"])
for s in sorted(stacks, key=lambda s: (s["_region"], s["StackName"])):
    if s.get("ParentId"): continue
    upd = s.get("LastUpdatedTime") or s["CreationTime"]
    idle = (now - dt.datetime.fromisoformat(upd.replace("Z", "+00:00"))).days
    res = nres.get((s["_region"], s["StackName"]), [])
    types = {}
    for x in res: types[x["ResourceType"]] = types.get(x["ResourceType"], 0) + 1
    top = ",".join(f"{k.split('::',1)[1]}x{v}" for k, v in sorted(types.items(), key=lambda kv: -kv[1])[:5])
    cdk = "cdk" if "AWS::CDK::Metadata" in types else ""
    w.writerow([s["_region"], s["StackName"], s["StackStatus"], s["CreationTime"][:10], upd[:10], idle, len(res), top, cdk,
                ",".join(sorted(set(hits.get(s["StackName"], [])))), s.get("EnableTerminationProtection"),
                (s.get("DriftInformation") or {}).get("StackDriftStatus"), (s.get("Description") or "")[:80]])
