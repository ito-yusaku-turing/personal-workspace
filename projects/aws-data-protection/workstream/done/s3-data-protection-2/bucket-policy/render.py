"""今のバケットポリシーに 2 文を足した全文を作り、IAM Access Analyzer で検証する（読み取りだけ）。

使い方: python3 -I render.py <出力先ディレクトリ> <バケット>...
AWS のプロファイルは readonly を使う。
"""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROFILE = ["--profile", "readonly", "--region", "us-west-2"]


def aws(*args):
    r = subprocess.run(["aws", *args, *PROFILE, "--output", "json"], capture_output=True, text=True)
    return r


def render(bucket):
    tmpl = open(os.path.join(HERE, "statements.json")).read().replace("${BUCKET}", bucket)
    new = json.loads(tmpl)["Statement"]
    r = aws("s3api", "get-bucket-policy", "--bucket", bucket)
    if r.returncode == 0:
        cur = json.loads(json.loads(r.stdout)["Policy"])
    elif "NoSuchBucketPolicy" in r.stderr:
        cur = {"Version": "2012-10-17", "Statement": []}
    else:
        sys.exit(r.stderr)
    sids = {s["Sid"] for s in new}
    cur["Statement"] = [s for s in cur["Statement"] if s.get("Sid") not in sids] + new
    return cur


def validate(policy):
    r = aws("accessanalyzer", "validate-policy", "--policy-type", "RESOURCE_POLICY",
            "--validate-policy-resource-type", "AWS::S3::Bucket",
            "--policy-document", json.dumps(policy))
    if r.returncode != 0:
        sys.exit(r.stderr)
    return json.loads(r.stdout)["findings"]


out = sys.argv[1]
os.makedirs(out, exist_ok=True)
for b in sys.argv[2:]:
    p = render(b)
    json.dump(p, open(os.path.join(out, f"{b}.json"), "w"), indent=2, ensure_ascii=False)
    f = validate(p)
    print(b, len(p["Statement"]), "文", "指摘なし" if not f else
          "; ".join(f"{x['findingType']}:{x['issueCode']}" for x in f))
