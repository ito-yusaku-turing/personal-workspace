#!/usr/bin/env python3
"""IAM ロールの一覧に、最終利用・信頼する主体・強い権限の有無を付けて TSV で出す。
  python3 -I iam_roles.py <取得日のフォルダ>
"""
import csv, json, sys, datetime as dt, urllib.parse
base = sys.argv[1]
now = dt.datetime(2026, 10, 28, tzinfo=dt.timezone.utc)
auth = json.load(open(f"{base}/global/iam/get-account-authorization-details.json"))
ACCOUNT = "767397804933"
STRONG = {"AdministratorAccess", "PowerUserAccess", "IAMFullAccess", "AmazonS3FullAccess", "SecretsManagerReadWrite"}

def doc(x):
    return json.loads(urllib.parse.unquote(x)) if isinstance(x, str) else x

def principals(trust):
    out = []
    sts = trust.get("Statement", [])
    for st in sts if isinstance(sts, list) else [sts]:
        if st.get("Effect") != "Allow": continue
        p = st.get("Principal", {})
        if p == "*": out.append("*"); continue
        for k, v in p.items():
            for x in (v if isinstance(v, list) else [v]):
                out.append(f"{k}:{x}")
        cond = st.get("Condition")
        if any(k.startswith("Federated") for k in p) and cond:
            out.append("cond=" + json.dumps(cond, separators=(",", ":")))
    return out

def wildcard_actions(policy_doc):
    hits = []
    sts = doc(policy_doc).get("Statement", []) if policy_doc else []
    for st in sts if isinstance(sts, list) else [sts]:
        if st.get("Effect") != "Allow": continue
        acts = st.get("Action", [])
        acts = acts if isinstance(acts, list) else [acts]
        res = st.get("Resource", [])
        res = res if isinstance(res, list) else [res]
        for a in acts:
            if a == "*" or a.endswith(":*") or a in ("iam:PassRole",) or a.startswith("iam:Create") or a.startswith("iam:Put") or a.startswith("iam:Attach"):
                hits.append(f"{a}@{'*' if '*' in res else 'scoped'}")
    return hits

pol = {p["Arn"]: p for p in auth["Policies"]}
def managed_doc(arn):
    p = pol.get(arn)
    if not p: return None
    for v in p["PolicyVersionList"]:
        if v["IsDefaultVersion"]: return v["Document"]

w = csv.writer(sys.stdout, delimiter="\t")
w.writerow(["role", "path", "created", "last_used", "last_region", "idle_days", "kind", "trust", "external", "managed", "strong", "risky_actions", "tags"])
for r in sorted(auth["RoleDetailList"], key=lambda r: r["RoleName"]):
    lu = (r.get("RoleLastUsed") or {}).get("LastUsedDate")
    last = dt.datetime.fromisoformat(lu.replace("Z", "+00:00")) if lu else None
    created = dt.datetime.fromisoformat(r["CreateDate"].replace("Z", "+00:00"))
    idle = (now - (last or created)).days
    trust = principals(doc(r["AssumeRolePolicyDocument"]))
    ext = [t for t in trust if t.startswith("AWS:") and ACCOUNT not in t]
    path, name = r["Path"], r["RoleName"]
    kind = ("service-linked" if path.startswith("/aws-service-role/") else
            "sso" if name.startswith("AWSReservedSSO_") else
            "controltower" if name.startswith(("aws-controltower-", "AWSControlTower")) or "stacksets-exec" in name else
            "cdk-bootstrap" if name.startswith("cdk-hnb659fds-") else "other")
    managed = [p["PolicyName"] for p in r.get("AttachedManagedPolicies", [])]
    risky = []
    for p in r.get("AttachedManagedPolicies", []):
        if p["PolicyArn"].startswith(f"arn:aws:iam::{ACCOUNT}:"):
            risky += wildcard_actions(managed_doc(p["PolicyArn"]))
    for ip in r.get("RolePolicyList", []):
        risky += wildcard_actions(ip["PolicyDocument"])
    tags = ",".join(f"{t['Key']}={t['Value']}" for t in r.get("Tags", []))
    w.writerow([name, path, r["CreateDate"][:10], (lu or "")[:10], (r.get("RoleLastUsed") or {}).get("Region", ""), idle, kind,
                ";".join(trust), ";".join(ext), ";".join(managed), ";".join(sorted(STRONG & set(managed))),
                ";".join(sorted(set(risky)))[:300], tags[:200]])
