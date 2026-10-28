#!/usr/bin/env python3
"""IAM ユーザーの一覧に、最終利用・キー・権限の要約を付けて TSV で出す。
  python3 -I iam_users.py <取得日のフォルダ>
"""
import csv, json, sys, datetime as dt
base = sys.argv[1]
now = dt.datetime(2026, 10, 28, tzinfo=dt.timezone.utc)
auth = json.load(open(f"{base}/global/iam/get-account-authorization-details.json"))
rep = {r["user"]: r for r in csv.DictReader(open(f"{base}/global/iam/get-credential-report.csv"))}
groups = {g["GroupName"]: g for g in auth["GroupDetailList"]}

def d(s):
    if not s or s in ("N/A", "no_information", "not_supported"): return None
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
def age(x): return (now - x).days if x else None

out = csv.writer(sys.stdout, delimiter="\t")
out.writerow(["user","created","console","pw_last_used","mfa","key1","key1_rot","key1_used","key1_svc","key2","key2_used","last_any","idle_days","groups","managed","inline","path","tags"])
for u in sorted(auth["UserDetailList"], key=lambda u: u["UserName"]):
    r = rep.get(u["UserName"], {})
    used = [d(r.get("password_last_used")), d(r.get("access_key_1_last_used_date")), d(r.get("access_key_2_last_used_date"))]
    used = [x for x in used if x]
    last = max(used) if used else None
    managed = [p["PolicyName"] for p in u.get("AttachedManagedPolicies", [])]
    for g in u.get("GroupList", []):
        managed += [f"{g}:{p['PolicyName']}" for p in groups.get(g, {}).get("AttachedManagedPolicies", [])]
    inline = [p["PolicyName"] for p in u.get("UserPolicyList", [])]
    tags = ",".join(f"{t['Key']}={t['Value']}" for t in u.get("Tags", []))
    out.writerow([u["UserName"], u["CreateDate"][:10], r.get("password_enabled"), (r.get("password_last_used") or "")[:10], r.get("mfa_active"),
        r.get("access_key_1_active"), (r.get("access_key_1_last_rotated") or "")[:10], (r.get("access_key_1_last_used_date") or "")[:10], r.get("access_key_1_last_used_service"),
        r.get("access_key_2_active"), (r.get("access_key_2_last_used_date") or "")[:10],
        last.date().isoformat() if last else "never", age(last) if last else age(d(u["CreateDate"])),
        ",".join(u.get("GroupList", [])), ";".join(managed), ";".join(inline), u["Path"], tags[:120]])
