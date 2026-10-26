#!/bin/bash
# 使い方: synth-compare.sh <cdk-apps のチェックアウト> <出力先>
# 4 スタックを cdk.json の context 込みで synth する（Docker が無くても動くよう、バンドルは飛ばす）
SRC=$1; OUT=$2; FAKE=$(mktemp -d); printf '#!/bin/sh\nexit 0\n' > $FAKE/docker; chmod +x $FAKE/docker
export PATH=$FAKE:$PATH CDK_DEFAULT_ACCOUNT=767397804933 CDK_DEFAULT_REGION=us-west-2
cd $SRC
for a in datalake gaming-data-collection denso-taxi denso-nx; do
  ctx=$(python3 -I -c "import json,sys;c=json.load(open(sys.argv[1])).get('context',{});cc=json.load(open(sys.argv[2])) if __import__('os').path.exists(sys.argv[2]) else {};c.update(cc);c['aws:cdk:bundling-stacks']=[];print(json.dumps(c))" apps/$a/cdk.json apps/$a/cdk.context.json)
  runner="npx ts-node --prefer-ts-exts"; [ $a = datalake ] && runner="npx tsx"
  (cd apps/$a && rm -rf $OUT/$a && CDK_OUTDIR=$OUT/$a CDK_CONTEXT_JSON="$ctx" $runner bin/$a.ts >/dev/null 2>&1; echo "$a exit $?")
done
