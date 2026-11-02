"""通知の仕組みを外せる主体を、IAM の設定（get-account-authorization-details）から手元で判定する。
Quick Win プランの作業 4。通知の部品はまだ無いので、仮の名前（original-bucket-alert）で、外す・黙らせる操作の権限を見る。
判定のしかたは escalation.py と同じ（条件付きの Allow は「conditional」、権限の境界も見る。SCP とリソースのポリシーは見ない）。
使い方: python3 -I notification-tamper.py iam.json out.json"""
import json, fnmatch, sys, collections
A = "767397804933"
R = "us-west-2"
d = json.load(open(sys.argv[1]))
pol = {p["Arn"]: [v for v in p["PolicyVersionList"] if v["IsDefaultVersion"]][0]["Document"] for p in d["Policies"]}
L = lambda x: x if isinstance(x, list) else [x]
def doc(x): return json.loads(x) if isinstance(x, str) else x
def m(pats, v): return any(fnmatch.fnmatchcase(v.lower(), p.lower()) for p in L(pats))

N = "original-bucket-alert"
RULE = f"arn:aws:events:{R}:{A}:rule/{N}"
TOPIC = f"arn:aws:sns:{R}:{A}:{N}"
FUNC = f"arn:aws:lambda:{R}:{A}:function:{N}"
SECRET = f"arn:aws:secretsmanager:{R}:{A}:secret:{N}-AbCdEf"
TRAIL = f"arn:aws:cloudtrail:{R}:{A}:trail/original-bucket-audit"
BUCKET = f"arn:aws:s3:::td1-raw-{A}"
# (群, 名前, アクション, 資源)
CHECKS = [
    ("ルール", "ルールの削除", "events:DeleteRule", RULE),
    ("ルール", "ルールの無効化", "events:DisableRule", RULE),
    ("ルール", "ルールの書き換え", "events:PutRule", RULE),
    ("ルール", "送り先の取り外し", "events:RemoveTargets", RULE),
    ("ルール", "送り先の差し替え", "events:PutTargets", RULE),
    ("送り先", "SNS のトピックの削除", "sns:DeleteTopic", TOPIC),
    ("送り先", "SNS のトピックの設定の変更", "sns:SetTopicAttributes", TOPIC),
    ("送り先", "Lambda の削除", "lambda:DeleteFunction", FUNC),
    ("送り先", "Lambda のコードの差し替え", "lambda:UpdateFunctionCode", FUNC),
    ("送り先", "Lambda の同時実行を 0 にする", "lambda:PutFunctionConcurrency", FUNC),
    ("送り先", "Slack の鍵の書き換え", "secretsmanager:PutSecretValue", SECRET),
    ("送り先", "Slack の鍵の削除", "secretsmanager:DeleteSecret", SECRET),
    ("バケット", "バケットの通知の設定の変更", "s3:PutBucketNotification", BUCKET),
    ("証跡", "証跡の停止", "cloudtrail:StopLogging", TRAIL),
    ("証跡", "証跡の削除", "cloudtrail:DeleteTrail", TRAIL),
    ("証跡", "記録の対象の変更", "cloudtrail:PutEventSelectors", TRAIL),
]
# 権限の昇格（何でも自分に付けられる）。escalation.py と同じ
ANYROLE = f"arn:aws:iam::{A}:role/some-role"
ANYUSER = f"arn:aws:iam::{A}:user/some-user"
ANYPOL = f"arn:aws:iam::{A}:policy/some-policy"
ESC = [
    ("昇格", "ロールにポリシーを付ける", "iam:AttachRolePolicy", ANYROLE),
    ("昇格", "ロールにインラインを書く", "iam:PutRolePolicy", ANYROLE),
    ("昇格", "ロールの信頼の変更", "iam:UpdateAssumeRolePolicy", ANYROLE),
    ("昇格", "ユーザーにポリシーを付ける", "iam:AttachUserPolicy", ANYUSER),
    ("昇格", "ユーザーにインラインを書く", "iam:PutUserPolicy", ANYUSER),
    ("昇格", "ポリシーの版の作成", "iam:CreatePolicyVersion", ANYPOL),
]

def statements(e):
    for ip in e.get("RolePolicyList", []) + e.get("UserPolicyList", []):
        yield ip["PolicyName"], doc(ip["PolicyDocument"])
    for ap in e.get("AttachedManagedPolicies", []):
        yield ap["PolicyName"], doc(pol[ap["PolicyArn"]]) if ap["PolicyArn"] in pol else None
    for g in e.get("GroupList", []):
        for gd in d.get("GroupDetailList", []):
            if gd["GroupName"] != g: continue
            for ip in gd.get("GroupPolicyList", []): yield ip["PolicyName"], doc(ip["PolicyDocument"])
            for ap in gd.get("AttachedManagedPolicies", []):
                yield ap["PolicyName"], doc(pol[ap["PolicyArn"]]) if ap["PolicyArn"] in pol else None

def evaluate(stmts, action, res):
    allow = cond = deny = False
    for name, dc in stmts:
        if dc is None: continue
        for s in L(dc["Statement"]):
            a_ok = ("Action" in s and m(s["Action"], action)) or ("NotAction" in s and not m(s["NotAction"], action))
            r_ok = ("Resource" in s and m(s["Resource"], res)) or ("NotResource" in s and not m(s["NotResource"], res))
            if not (a_ok and r_ok): continue
            if s["Effect"] == "Deny" and "Condition" not in s: deny = True
            elif s["Effect"] == "Allow":
                if "Condition" in s: cond = True
                else: allow = True
    if deny: return "deny"
    return "allow" if allow else ("conditional" if cond else "none")

def check(e, action, r):
    v = evaluate(list(statements(e)), action, r)
    pb = e.get("PermissionsBoundary", {}).get("PermissionsBoundaryArn")
    if pb and v in ("allow", "conditional"):
        b = evaluate([("boundary", doc(pol.get(pb)) if pb in pol else None)], action, r)
        if b in ("none", "deny"): v = "none"
        elif b == "conditional": v = "conditional"
    return v

ents = d["RoleDetailList"] + d["UserDetailList"]
arn = {e["Arn"]: e for e in ents}
res = {}
for e in ents:
    hits = {}
    for grp, name, act, r in CHECKS + ESC:
        v = check(e, act, r)
        if v != "none" and v != "deny": hits[f"{grp}: {name}"] = v
    if hits: res[e["Arn"]] = hits

# 乗り継ぎ: 判定に当たった主体を引き受けられる主体（escalation.py と同じ考え方）
def trust(r):
    out = []
    for s in L(doc(r.get("AssumeRolePolicyDocument", {"Statement": []}))["Statement"]):
        if s.get("Effect") != "Allow": continue
        p = s.get("Principal", {})
        if isinstance(p, dict):
            for k, v in p.items(): out += [f"{k}:{x}" for x in L(v)]
        else: out.append(str(p))
    return out
via = collections.defaultdict(list)
for r in d["RoleDetailList"]:
    if r["Arn"] not in res: continue
    tr = [t.split(":", 1)[1] for t in trust(r) if t.startswith("AWS:")]
    if not tr: continue
    for e in ents:
        if e["Arn"] == r["Arn"] or e["Arn"] in res: continue
        if any(t == "*" or t in (f"arn:aws:iam::{A}:root", A) or t == e["Arn"] for t in tr) and check(e, "sts:AssumeRole", r["Arn"]) in ("allow", "conditional"):
            via[e["Arn"]].append(r["Arn"])

EXEMPT = ("AWSReservedSSO_FullAccess_", "AWSReservedSSO_AWSAdministratorAccess_")
out = []
for a, h in sorted(res.items()):
    e = arn[a]
    groups = sorted({k.split(":")[0] for k in h})
    out.append({"arn": a, "exempt": any(x in a for x in EXEMPT), "groups": groups,
                "all_conditional": all(v == "conditional" for v in h.values()), "hits": h,
                "last_used": (e.get("RoleLastUsed") or {}).get("LastUsedDate"),
                "trust": trust(e) if "RoleName" in e else ["(user)"]})
via_out = [{"arn": a, "via": v, "last_used": (arn[a].get("RoleLastUsed") or {}).get("LastUsedDate")} for a, v in sorted(via.items())]
json.dump({"direct": out, "via": via_out}, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
c = collections.Counter()
for o in out:
    for g in o["groups"]: c[(g, "conditional" if all(v == "conditional" for k, v in o["hits"].items() if k.startswith(g)) else "allow")] += 1
print("principals:", len(ents), "direct:", len(out), "via assume:", len(via_out))
for (g, k), n in sorted(c.items()): print(f"  {g} {k}: {n}")
