"""IAM の設定（get-account-authorization-details）から、原本バケットの例外を名乗れる主体を手元で判定する。
条件付きの Allow・権限の境界は「要確認」として分け、シミュレーターで確かめ直す。"""
import json, fnmatch, sys, collections
A = "767397804933"
d = json.load(open(sys.argv[1]))
pol = {p["Arn"]: [v for v in p["PolicyVersionList"] if v["IsDefaultVersion"]][0]["Document"] for p in d["Policies"]}
L = lambda x: x if isinstance(x, list) else [x]
def doc(x): return json.loads(x) if isinstance(x, str) else x
def m(pats, v): return any(fnmatch.fnmatchcase(v.lower(), p.lower()) for p in L(pats))
REG = ["us-west-2", "ap-northeast-1", "us-east-1", "us-east-2"]
DEPLOY = [f"arn:aws:iam::{A}:role/cdk-hnb659fds-deploy-role-{A}-{r}" for r in REG]
CFNX = [f"arn:aws:iam::{A}:role/cdk-hnb659fds-cfn-exec-role-{A}-{r}" for r in REG]
NEWCFN = f"arn:aws:iam::{A}:role/cdk-hnb659fds-cfn-exec-role-{A}-zz-new"
ANYROLE = f"arn:aws:iam::{A}:role/some-role"
ANYUSER = f"arn:aws:iam::{A}:user/some-user"
ANYPOL = f"arn:aws:iam::{A}:policy/some-policy"
# (名前, アクション, 資源の候補)
CHECKS = [
    ("deploy のロールの引き受け", "sts:AssumeRole", DEPLOY),
    ("cfn-exec の名前のロールの作成", "iam:CreateRole", [NEWCFN]),
    ("cfn-exec・deploy の信頼の変更", "iam:UpdateAssumeRolePolicy", CFNX + DEPLOY),
    ("cfn-exec を渡す", "iam:PassRole", CFNX),
    ("ロールにポリシーを付ける", "iam:AttachRolePolicy", [ANYROLE]),
    ("ロールにインラインを書く", "iam:PutRolePolicy", [ANYROLE]),
    ("ロールの信頼の変更", "iam:UpdateAssumeRolePolicy", [ANYROLE]),
    ("ユーザーにポリシーを付ける", "iam:AttachUserPolicy", [ANYUSER]),
    ("ユーザーにインラインを書く", "iam:PutUserPolicy", [ANYUSER]),
    ("アクセスキーの作成", "iam:CreateAccessKey", [ANYUSER]),
    ("ログインの作成・変更", "iam:CreateLoginProfile", [ANYUSER]),
    ("ポリシーの版の作成", "iam:CreatePolicyVersion", [ANYPOL]),
]
CFN = ("cloudformation:CreateStack", ["*"])

def statements(e):
    for ip in e.get("RolePolicyList", []) + e.get("UserPolicyList", []):
        yield ip["PolicyName"], doc(ip["PolicyDocument"])
    for ap in e.get("AttachedManagedPolicies", []):
        if ap["PolicyArn"] in pol: yield ap["PolicyName"], doc(pol[ap["PolicyArn"]])
        else: yield ap["PolicyName"], None

def evaluate(stmts, action, res):
    """allow / conditional / deny / none を返す（その資源について）"""
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

def check(e, action, resources):
    st = list(statements(e))
    pb = e.get("PermissionsBoundary", {}).get("PermissionsBoundaryArn")
    best = "none"
    for r in resources:
        v = evaluate(st, action, r)
        if pb and v in ("allow", "conditional"):
            b = evaluate([("boundary", doc(pol.get(pb)) if pb in pol else None)], action, r)
            if b == "none" or b == "deny": v = "none"
            elif b == "conditional": v = "conditional"
        rank = {"none": 0, "deny": 0, "conditional": 1, "allow": 2}
        if rank[v] > rank[best]: best = v
    return best

ents = d["RoleDetailList"] + d["UserDetailList"]
arn = {e["Arn"]: e for e in ents}
res = {}
for e in ents:
    hits = {}
    for name, act, rs in CHECKS:
        v = check(e, act, rs)
        if v != "none": hits[name] = v
    if "cfn-exec を渡す" in hits:
        c = check(e, *CFN)
        if c == "none": hits["cfn-exec を渡す"] += "(スタック作成なし)"
    res[e["Arn"]] = hits
POWER = {a for a, h in res.items() if any(not v.endswith("(スタック作成なし)") for v in h.values())}

# 乗り継ぎ: 主体 P が、ロール R を引き受けられるか（P の sts:AssumeRole と R の信頼）
def trust_aws(r):
    out = []
    for s in L(doc(r.get("AssumeRolePolicyDocument", {"Statement": []}))["Statement"]):
        if s.get("Effect") != "Allow": continue
        p = s.get("Principal", {})
        if isinstance(p, dict): out += L(p.get("AWS", []))
        elif p == "*": out.append("*")
    return out
edges = collections.defaultdict(set)
roles = d["RoleDetailList"]
for r in roles:
    tr = trust_aws(r)
    if not tr: continue
    for e in ents:
        if e["Arn"] == r["Arn"]: continue
        ok = any(t == "*" or t in (f"arn:aws:iam::{A}:root", A) or t == e["Arn"] for t in tr)
        if ok and check(e, "sts:AssumeRole", [r["Arn"]]) != "none": edges[e["Arn"]].add(r["Arn"])
def reach(a, seen=None):
    seen = seen or set()
    for b in edges[a]:
        if b not in seen: seen.add(b); reach(b, seen)
    return seen
VIA = {}
for e in ents:
    via = sorted(x for x in reach(e["Arn"]) if x in POWER)
    if via and e["Arn"] not in POWER: VIA[e["Arn"]] = via

# 外から入れる: 強いロールの信頼（他のアカウント・サービス・SAML）
def trust_all(r):
    out = []
    for s in L(doc(r.get("AssumeRolePolicyDocument", {"Statement": []}))["Statement"]):
        if s.get("Effect") != "Allow": continue
        p = s.get("Principal", {})
        if isinstance(p, dict):
            for k, v in p.items(): out += [f"{k}:{x}" for x in L(v)]
        else: out.append(str(p))
    return out
out = {"power": [], "via": [], "conditional_only": []}
for a in sorted(POWER):
    e = arn[a]
    entry = {"arn": a, "hits": res[a], "last_used": (e.get("RoleLastUsed") or {}).get("LastUsedDate"), "trust": trust_all(e) if "RoleName" in e else ["(user)"]}
    (out["conditional_only"] if all(v.startswith("conditional") for v in res[a].values()) else out["power"]).append(entry)
for a, via in sorted(VIA.items()):
    out["via"].append({"arn": a, "via": via, "last_used": (arn[a].get("RoleLastUsed") or {}).get("LastUsedDate")})
json.dump(out, open(sys.argv[2], "w"), ensure_ascii=False, indent=1)
print("principals:", len(ents), "power:", len(out["power"]), "conditional only:", len(out["conditional_only"]), "via assume:", len(out["via"]))
