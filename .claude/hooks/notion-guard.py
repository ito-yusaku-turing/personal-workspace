#!/usr/bin/env python3
"""Notion の MCP ツールを、許可した操作だけに絞る PreToolUse フック。

許可する操作（docs/development-environment.md の「Notion（MCP）」）:
- 指定したページを読む（notion-fetch）
- ページを新しく作る（notion-create-pages）
- 指定したページの内容を更新する（notion-update-page。ローカルの原本との同期に使う）
- 指定したページのコメントを読む（notion-get-comments）

ここに無いツールは、Notion が後から足したものも含めてすべて止める。
"""

import json
import sys

PREFIX = "mcp__notion__"
ALLOWED = {"notion-fetch", "notion-create-pages", "notion-update-page", "notion-get-comments"}
# 更新で許すコマンド。テンプレートの適用と検証済みの設定は、同期の範囲を超えるので止める
UPDATE_COMMANDS = {"update_content", "replace_content", "insert_content", "update_properties"}


def deny(reason: str) -> None:
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": f"notion-guard: {reason}",
        }
    }, ensure_ascii=False))
    sys.exit(0)


def check(tool: str, args: dict) -> None:
    if tool not in ALLOWED:
        deny(f"{tool} は許可していない（許可: {', '.join(sorted(ALLOWED))}）")

    if tool == "notion-fetch":
        if str(args.get("id", "")).strip() == "memory":
            deny("Notion のメモリは読まない（読むのは指定したページだけ）")

    elif tool == "notion-create-pages":
        if args.get("parent") == "memory":
            deny("Notion のメモリには保存しない")
        if any(p.get("is_skill") for p in args.get("pages") or [] if isinstance(p, dict)):
            deny("ページをスキルにしない")

    elif tool == "notion-update-page":
        command = args.get("command")
        if command not in UPDATE_COMMANDS:
            deny(f"更新のコマンド {command} は許可していない（許可: {', '.join(sorted(UPDATE_COMMANDS))}）")
        if args.get("allow_deleting_content"):
            deny("子ページ・データベースを消す更新（allow_deleting_content）はしない")
        if "is_skill" in args:
            deny("スキルの設定は変えない")


def main() -> None:
    payload = json.load(sys.stdin)
    name = payload.get("tool_name", "")
    if not name.startswith(PREFIX):
        return
    args = payload.get("tool_input") or {}
    check(name[len(PREFIX):], args if isinstance(args, dict) else {})


if __name__ == "__main__":
    main()
