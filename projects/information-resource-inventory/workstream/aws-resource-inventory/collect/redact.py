#!/usr/bin/env python3
"""AWS の応答（JSON）から機微な値を伏せ字にする。標準入力 → 標準出力。

- キー名で伏せる: 環境変数・ジョブの引数・UserData・パスワードなど。キー名は残し、値を <REDACTED> にする。
- 値の形で伏せる: アクセスキーの ID（末尾 4 文字だけ残す）・Slack のトークン・JWT・秘密鍵など、よく知られた形の文字列。
伏せた件数を標準エラーに出す。
"""
import json
import re
import sys

R = "<REDACTED>"

# 値をまるごと伏せるキー（中が dict なら各値、list なら各要素を伏せる）
WHOLE_KEYS = {
    "Variables",            # Lambda の Environment.Variables
    "DefaultArguments",     # Glue のジョブ
    "NonOverridableArguments",
    "UserData",
    "SecretString", "SecretBinary",
    "Password", "MasterUserPassword", "AuthToken",
    "PrivateKey", "KeyMaterial",
    "SessionToken", "SecretAccessKey",
}
# {name/Name: ..., value/Value: ...} の list で値を伏せるキー（ECS・CodeBuild・Batch など）
NAME_VALUE_LIST_KEYS = {"environment", "Environment", "EnvironmentVariables", "secrets"}

# アクセスキーの ID は、突き合わせに使えるよう末尾 4 文字を残す（AWS のコンソールと同じ見せ方）
KEY_ID = re.compile(r"(?<![A-Z0-9])(AKIA|ASIA)[A-Z0-9]{12}([A-Z0-9]{4})(?![A-Z0-9])")

PATTERNS = [
    re.compile(r"xox[abposr]-[A-Za-z0-9-]{10,}"),
    re.compile(r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"(?i)(sk|pk|rk)_(live|test)_[A-Za-z0-9]{10,}"),
    re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"(?i)(postgres(ql)?|mysql|mongodb(\+srv)?|redis)://[^:/\s]+:[^@\s]+@"),
    re.compile(r"https://hooks\.slack\.com/[A-Za-z0-9/_-]+"),
]

count = 0


def scrub_str(s):
    global count
    s, n = KEY_ID.subn(lambda m: m.group(1) + "…" + m.group(2), s)
    count += n
    for p in PATTERNS:
        s, n = p.subn(R, s)
        count += n
    return s


def blank(v):
    global count
    if isinstance(v, dict):
        count += len(v)
        return {k: R for k in v}
    if isinstance(v, list):
        count += len(v)
        return [blank(x) if isinstance(x, (dict, list)) else R for x in v]
    if v in (None, ""):
        return v
    count += 1
    return R


def walk(o):
    if isinstance(o, dict):
        out = {}
        for k, v in o.items():
            if k in WHOLE_KEYS:
                out[k] = blank(v)
            elif k in NAME_VALUE_LIST_KEYS and isinstance(v, list) and all(isinstance(x, dict) for x in v):
                out[k] = [nv(x) for x in v]
            elif k in NAME_VALUE_LIST_KEYS and isinstance(v, dict) and "Variables" not in v:
                out[k] = blank(v)
            else:
                out[k] = walk(v)
        return out
    if isinstance(o, list):
        return [walk(x) for x in o]
    if isinstance(o, str):
        return scrub_str(o)
    return o


def nv(x):
    global count
    y = dict(x)
    for vk in ("value", "Value", "valueFrom", "ValueFrom"):
        if vk in y and y[vk] not in (None, ""):
            y[vk] = R
            count += 1
    return walk(y)


def main():
    data = sys.stdin.read()
    if not data.strip():
        return
    out = walk(json.loads(data))
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)
    sys.stdout.write("\n")
    print(count, file=sys.stderr)


if __name__ == "__main__":
    main()
