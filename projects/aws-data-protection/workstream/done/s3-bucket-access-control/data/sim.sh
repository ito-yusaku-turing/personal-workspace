#!/bin/sh
# $1 = principal ARN
D=$(dirname "$0"); n=$(echo "$1" | sed 's#[:/]#_#g')
[ -s "$D/sim/$n.b.json" ] && [ -s "$D/sim/$n.o.json" ] && exit 0
BR=$(sed 's#^#arn:aws:s3:::#' "$D/buckets.txt" | tr '\n' ' ')
OR=$(sed 's#^\(.*\)$#arn:aws:s3:::\1/x#' "$D/buckets.txt" | tr '\n' ' ')
aws iam simulate-principal-policy --policy-source-arn "$1" --action-names s3:PutBucketVersioning s3:PutLifecycleConfiguration s3:PutBucketPolicy s3:DeleteBucketPolicy s3:PutBucketObjectLockConfiguration s3:DeleteBucket --resource-arns $BR --query 'EvaluationResults[].{a:EvalActionName,d:EvalDecision,r:ResourceSpecificResults[].{r:EvalResourceName,d:EvalResourceDecision,m:MatchedStatements[].SourcePolicyId},m:MatchedStatements[].SourcePolicyId,ctx:MissingContextValues}' --output json > "$D/sim/$n.b.json" 2>"$D/sim/$n.b.err"
aws iam simulate-principal-policy --policy-source-arn "$1" --action-names s3:DeleteObjectVersion s3:DeleteObject s3:PutObject --resource-arns $OR --query 'EvaluationResults[].{a:EvalActionName,d:EvalDecision,r:ResourceSpecificResults[].{r:EvalResourceName,d:EvalResourceDecision,m:MatchedStatements[].SourcePolicyId},m:MatchedStatements[].SourcePolicyId,ctx:MissingContextValues}' --output json > "$D/sim/$n.o.json" 2>"$D/sim/$n.o.err"
