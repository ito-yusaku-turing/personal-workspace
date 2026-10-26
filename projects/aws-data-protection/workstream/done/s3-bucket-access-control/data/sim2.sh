#!/bin/sh
# $1 = principal ARN
CTX="ContextKeyName=s3:ResourceAccount,ContextKeyValues=767397804933,ContextKeyType=string ContextKeyName=aws:ResourceAccount,ContextKeyValues=767397804933,ContextKeyType=string ContextKeyName=aws:PrincipalAccount,ContextKeyValues=767397804933,ContextKeyType=string ContextKeyName=aws:SecureTransport,ContextKeyValues=true,ContextKeyType=boolean"
D=$(dirname "$0"); n=$(echo "$1" | sed 's#[:/]#_#g')
[ -s "$D/sim2/$n.b.json" ] && [ -s "$D/sim2/$n.o.json" ] && exit 0
BR=$(sed 's#^#arn:aws:s3:::#' "$D/buckets.txt" | tr '\n' ' ')
OR=$(sed 's#^\(.*\)$#arn:aws:s3:::\1/x#' "$D/buckets.txt" | tr '\n' ' ')
aws iam simulate-principal-policy --policy-source-arn "$1" --action-names s3:PutBucketVersioning s3:PutLifecycleConfiguration s3:PutBucketPolicy s3:DeleteBucketPolicy s3:PutBucketObjectLockConfiguration s3:DeleteBucket --resource-arns $BR --context-entries $CTX --query 'EvaluationResults[].{a:EvalActionName,d:EvalDecision,r:ResourceSpecificResults[].{r:EvalResourceName,d:EvalResourceDecision,m:MatchedStatements[].SourcePolicyId},m:MatchedStatements[].SourcePolicyId,ctx:MissingContextValues}' --output json > "$D/sim2/$n.b.json" 2>"$D/sim2/$n.b.err"
aws iam simulate-principal-policy --policy-source-arn "$1" --action-names s3:DeleteObjectVersion s3:DeleteObject s3:PutObject --resource-arns $OR --context-entries $CTX --query 'EvaluationResults[].{a:EvalActionName,d:EvalDecision,r:ResourceSpecificResults[].{r:EvalResourceName,d:EvalResourceDecision,m:MatchedStatements[].SourcePolicyId},m:MatchedStatements[].SourcePolicyId,ctx:MissingContextValues}' --output json > "$D/sim2/$n.o.json" 2>"$D/sim2/$n.o.err"
