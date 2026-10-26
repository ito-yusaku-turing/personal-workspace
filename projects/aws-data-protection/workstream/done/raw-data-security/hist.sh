#!/bin/sh
# $1 = bucket name
b="$1"; base=$(echo "$b" | sed -E 's/-767397804933.*$//')
cd /usr/app/cdk-apps
n=$(git log --all -S"$base" --format='%h' -- . ':!node_modules' 2>/dev/null | wc -l)
first=$(git log --all -S"$base" --reverse --format='%h|%cs|%an|%s' -- . ':!node_modules' 2>/dev/null | head -1)
last=$(git log --all -S"$base" --format='%h|%cs|%an|%s' -- . ':!node_modules' 2>/dev/null | head -1)
files=$(git grep -l -F "$base" HEAD -- . ':!node_modules' ':!package-lock.json' 2>/dev/null | sed 's/^HEAD://' | head -8 | tr '\n' ',')
printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$b" "$base" "$n" "$first" "$last" "$files"
