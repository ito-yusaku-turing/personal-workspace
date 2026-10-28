#!/usr/bin/env python3
"""EventBridge のルール・S3 の通知・Lambda を突き合わせ、競合しかねないものを洗い出す。
  python3 -I conflicts.py <取得日のフォルダ>
出力（<取得日>/derived/）:
  events-rules.tsv   ルールごとの状態・出どころ・ターゲット・持ち主と、判定（dormant / dangling / ok）
  s3-notifications.tsv  バケットごとの通知と、通知を持つスタック（Managed）
  lambda.tsv          関数ごとの呼び出し回数（90 日）・最終更新・持ち主・呼び出し元
"""
import json, glob, os, sys, csv, re, datetime as dt
B = sys.argv[1]
now = dt.datetime(2026, 10, 28, tzinfo=dt.timezone.utc)
REGIONS = ["us-west-2", "ap-northeast-1"]
def load(p, default=None):
    try:
        with open(p) as f:
            t = f.read()
        return json.loads(t) if t.strip() else default
    except FileNotFoundError:
        return default

# --- 持ち主: 物理 ID → スタック
owner = {}
for f in glob.glob(f"{B}/*/cloudformation/resources/*.json"):
    reg, stack = f.split("/")[-4], os.path.basename(f)[:-5]
    for x in load(f)["StackResourceSummaries"]:
        pid = x.get("PhysicalResourceId") or ""
        owner[(reg, x["ResourceType"], pid)] = stack
        owner.setdefault(("*", pid), stack)
stack_repo = {(r["region"], r["stack"]): r["repos"] for r in csv.DictReader(open(f"{B}/derived/cfn-stacks.tsv"), delimiter="\t")}
parent = {}
for f in glob.glob(f"{B}/*/cloudformation/describe-stacks.json"):
    reg = f.split("/")[-3]
    ids = {s["StackId"]: s["StackName"] for s in load(f)["Stacks"]}
    for s in load(f)["Stacks"]:
        if s.get("RootId"): parent[(reg, s["StackName"])] = ids.get(s["RootId"], s["RootId"])
def own(reg, typ, pid):
    s = owner.get((reg, typ, pid)) or owner.get(("*", pid)) or ""
    root = parent.get((reg, s), s)
    return root, stack_repo.get((reg, root), "")

# --- 実在するもの
exists = set()
buckets = {b["Name"] for b in load(f"{B}/global/s3/list-buckets.json")["Buckets"]}
bucket_region = {}
for f in glob.glob(f"{B}/global/s3/location/*.json"):
    bucket_region[os.path.basename(f)[:-5]] = (load(f) or {}).get("LocationConstraint") or "us-east-1"
fns = {}
for reg in REGIONS:
    for fn in load(f"{B}/{reg}/lambda/list-functions.json", {"Functions": []})["Functions"]:
        fns[fn["FunctionArn"]] = (reg, fn)
        exists.add(fn["FunctionArn"])
    for t in load(f"{B}/{reg}/sns/list-topics.json", {"Topics": []})["Topics"]: exists.add(t["TopicArn"])
    for q in load(f"{B}/{reg}/sqs/list-queues.json", {}).get("QueueUrls", []) if load(f"{B}/{reg}/sqs/list-queues.json") else []:
        acct, name = q.split("/")[-2:]
        exists.add(f"arn:aws:sqs:{reg}:{acct}:{name}")
    for m in load(f"{B}/{reg}/stepfunctions/list-state-machines.json", {"stateMachines": []})["stateMachines"]: exists.add(m["stateMachineArn"])
    for q in load(f"{B}/{reg}/batch/describe-job-queues.json", {"jobQueues": []})["jobQueues"]: exists.add(q["jobQueueArn"])
    for c in load(f"{B}/{reg}/ecs/list-clusters.json", {"clusterArns": []})["clusterArns"]: exists.add(c)
    for d in load(f"{B}/{reg}/kinesis-firehose/list-delivery-streams.json", {"DeliveryStreamNames": []})["DeliveryStreamNames"]:
        exists.add(f"arn:aws:firehose:{reg}:767397804933:deliverystream/{d}")
    for bus in load(f"{B}/{reg}/events/list-event-buses.json")["EventBuses"]: exists.add(bus["Arn"])
def target_exists(arn):
    arn = re.sub(r":(\$LATEST|\d+|[A-Za-z0-9_-]+)$", "", arn) if arn.startswith("arn:aws:lambda") and arn.count(":") > 6 else arn
    svc = arn.split(":")[2]
    if svc in ("lambda", "sns", "sqs", "states", "batch", "ecs", "firehose", "events"):
        return arn in exists
    return None  # 確かめていない種類

# --- S3 の通知
notif = {}
for f in glob.glob(f"{B}/global/s3/notification/*.json"):
    notif[os.path.basename(f)[:-5]] = load(f, {}) or {}
eb_on = {b for b, n in notif.items() if "EventBridgeConfiguration" in n}

# 通知を持つスタック（Custom::S3BucketNotifications と、S3::Bucket の NotificationConfiguration）
managers = {}
for f in glob.glob(f"{B}/*/cloudformation/templates/*.json"):
    reg, stack = f.split("/")[-4], os.path.basename(f)[:-5]
    t = load(f)["TemplateBody"]
    if not isinstance(t, dict): continue
    for lid, r in (t.get("Resources") or {}).items():
        p = r.get("Properties") or {}
        if r.get("Type") == "Custom::S3BucketNotifications":
            bn = p.get("BucketName")
            if isinstance(bn, dict):
                ref = bn.get("Ref")
                bn = owner_name = None
                if ref:
                    for x in load(f"{B}/{reg}/cloudformation/resources/{stack}.json")["StackResourceSummaries"]:
                        if x["LogicalResourceId"] == ref: bn = x["PhysicalResourceId"]
            nc = p.get("NotificationConfiguration") or {}
            kinds = [k.replace("Configurations", "").replace("Configuration", "") for k in nc]
            managers.setdefault(bn or f"?{lid}", []).append(f"{parent.get((reg, stack), stack)}(Managed={str(p.get('Managed', True)).lower()}:{'+'.join(kinds) or 'empty'})")
        elif r.get("Type") == "AWS::S3::Bucket" and p.get("NotificationConfiguration"):
            bn = p.get("BucketName")
            if not isinstance(bn, str):
                for x in load(f"{B}/{reg}/cloudformation/resources/{stack}.json")["StackResourceSummaries"]:
                    if x["LogicalResourceId"] == lid: bn = x["PhysicalResourceId"]
            managers.setdefault(bn, []).append(f"{parent.get((reg, stack), stack)}(S3::Bucket:{'+'.join(p['NotificationConfiguration'])})")

with open(f"{B}/derived/s3-notifications.tsv", "w") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow(["bucket", "region", "eventbridge", "lambda", "sns", "sqs", "dangling", "managers", "bucket_owner", "flag"])
    for b in sorted(buckets):
        n = notif.get(b, {})
        lam = [c["LambdaFunctionArn"] for c in n.get("LambdaFunctionConfigurations", [])]
        sns = [c["TopicArn"] for c in n.get("TopicConfigurations", [])]
        sqs = [c["QueueArn"] for c in n.get("QueueConfigurations", [])]
        dang = [a for a in lam + sns + sqs if a.split(":")[3] in REGIONS and target_exists(a) is False]
        mg = managers.get(b, [])
        bo, _ = own(bucket_region.get(b, ""), "AWS::S3::Bucket", b)
        flags = []
        if any("Managed=true" in m for m in mg):
            flags.append("overwrite-owner")
            # 丸ごと上書きする持ち主の設定に無い通知は、その持ち主の次の deploy で消える
            if lam or sns or sqs: flags.append("extra-will-be-wiped")
        if len(mg) > 1: flags.append("multi-manager")
        if dang: flags.append("dangling")
        if (lam or sns or sqs or "EventBridgeConfiguration" in n) and not mg: flags.append("unmanaged-notification")
        w.writerow([b, bucket_region.get(b), "on" if b in eb_on else "", ";".join(x.split(":")[-1] for x in lam),
                    ";".join(x.split(":")[-1] for x in sns), ";".join(x.split(":")[-1] for x in sqs),
                    ";".join(dang), ";".join(mg), bo, ",".join(flags)])

# --- ルール
invoked_by = {}
with open(f"{B}/derived/events-rules.tsv", "w") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow(["region", "rule", "state", "source", "buckets", "schedule", "targets", "dangling", "owner", "repo", "verdict", "note"])
    for reg in REGIONS:
        for rf in glob.glob(f"{B}/{reg}/events/list-rules.*.json"):
            bus = os.path.basename(rf)[len("list-rules."):-5]
            for r in load(rf)["Rules"]:
                pat = json.loads(r["EventPattern"]) if r.get("EventPattern") else {}
                src = pat.get("source", [])
                det = pat.get("detail", {}) or {}
                bks = []
                bn = (det.get("bucket") or {}).get("name") if isinstance(det.get("bucket"), dict) else None
                for x in bn or []:
                    if isinstance(x, str): bks.append(x)
                    elif isinstance(x, dict) and "prefix" in x: bks += [b for b in buckets if b.startswith(x["prefix"])] or [x["prefix"] + "*(none)"]
                tg = load(f"{B}/{reg}/events/targets/{bus}.{r['Name']}.json", {"Targets": []})["Targets"]
                tarns = [t["Arn"] for t in tg]
                for a in tarns: invoked_by.setdefault(re.sub(r":(\$LATEST|\d+)$", "", a), []).append(f"rule:{r['Name']}({r['State']})")
                dang = [a for a in tarns if target_exists(a) is False]
                o, repo = own(reg, "AWS::Events::Rule", r["Name"])
                if not o: o, repo = own(reg, "AWS::Events::Rule", f"{bus}|{r['Name']}")
                verdict, note = "ok", []
                if dang: verdict = "dangling"; note.append("target missing")
                if not tarns: verdict = "no-target"
                if "aws.s3" in src and bks:
                    off = [b for b in bks if b not in eb_on]
                    if off and r["State"] == "ENABLED":
                        verdict = "dormant"; note.append("EventBridge off on " + ",".join(off))
                if r.get("ManagedBy"): verdict = "aws-managed"; note = [f"managed by {r['ManagedBy']}"]
                if r["State"] != "ENABLED": note.append(r["State"])
                w.writerow([reg, r["Name"], r["State"], ",".join(src) or "-", ",".join(bks), r.get("ScheduleExpression", ""),
                            ";".join(a.split(":", 5)[-1] for a in tarns), ";".join(dang), o, repo, verdict, "; ".join(note)])

# S3 → Lambda の呼び出し元
for b, n in notif.items():
    for c in n.get("LambdaFunctionConfigurations", []):
        invoked_by.setdefault(c["LambdaFunctionArn"], []).append(f"s3:{b}")
for reg in REGIONS:
    for m in load(f"{B}/{reg}/lambda/list-event-source-mappings.json", {"EventSourceMappings": []})["EventSourceMappings"]:
        invoked_by.setdefault(m["FunctionArn"], []).append(f"esm:{m.get('EventSourceArn','?').split(':')[-1]}({m.get('State')})")

# --- Lambda
inv = {}
for reg in REGIONS:
    for f in glob.glob(f"{B}/{reg}/cloudwatch/lambda-invocations-90d.*.json"):
        for r in load(f)["MetricDataResults"]:
            inv[(reg, r["Label"])] = sum(r["Values"])
with open(f"{B}/derived/lambda.tsv", "w") as out:
    w = csv.writer(out, delimiter="\t")
    w.writerow(["region", "function", "runtime", "last_modified", "invocations_90d", "owner", "repo", "invoked_by", "role"])
    for arn, (reg, fn) in sorted(fns.items()):
        o, repo = own(reg, "AWS::Lambda::Function", fn["FunctionName"])
        w.writerow([reg, fn["FunctionName"], fn.get("Runtime") or fn.get("PackageType"), fn["LastModified"][:10],
                    int(inv.get((reg, fn["FunctionName"]), 0)), o, repo, ";".join(invoked_by.get(arn, [])), fn["Role"].split("/")[-1]])
print("ok")
