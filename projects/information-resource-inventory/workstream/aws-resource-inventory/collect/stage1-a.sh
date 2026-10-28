#!/usr/bin/env bash
# 段階 1（優先度 A と、C の一部）: EC2・EBS・スナップショット・AMI・EIP・NAT・ELB・RDS・SageMaker・EKS・ECS・ECR・CloudWatch Logs・VPC。
#   stage1-a.sh <region>...
set -uo pipefail
C=$(dirname "$0")/cap.sh
base=${AWS_INV_DIR:-$HOME/aws/tuscenes-prod}/${AWS_INV_DATE:-$(date -u +%F)}
for r in "$@"; do
  "$C" "$r" ec2 describe-instances-full ec2 describe-instances --query 'Reservations[].Instances[].{InstanceId:InstanceId,State:State.Name,StateTransitionReason:StateTransitionReason,Type:InstanceType,LaunchTime:LaunchTime,Tags:Tags,IamInstanceProfile:IamInstanceProfile,SecurityGroups:SecurityGroups,VpcId:VpcId,ImageId:ImageId,KeyName:KeyName,MetadataOptions:MetadataOptions,PublicIpAddress:PublicIpAddress,Lifecycle:InstanceLifecycle,BlockDeviceMappings:BlockDeviceMappings}'
  "$C" "$r" ec2 describe-volumes ec2 describe-volumes
  "$C" "$r" ec2 describe-snapshots ec2 describe-snapshots --owner-ids self
  "$C" "$r" ec2 describe-images ec2 describe-images --owners self
  "$C" "$r" ec2 describe-addresses ec2 describe-addresses
  "$C" "$r" ec2 describe-nat-gateways ec2 describe-nat-gateways
  "$C" "$r" ec2 describe-vpcs ec2 describe-vpcs
  "$C" "$r" ec2 describe-subnets ec2 describe-subnets
  "$C" "$r" ec2 describe-vpc-endpoints ec2 describe-vpc-endpoints
  "$C" "$r" ec2 describe-key-pairs ec2 describe-key-pairs
  "$C" "$r" ec2 describe-launch-templates ec2 describe-launch-templates
  "$C" "$r" autoscaling describe-auto-scaling-groups autoscaling describe-auto-scaling-groups
  "$C" "$r" elbv2 describe-load-balancers elbv2 describe-load-balancers
  "$C" "$r" elbv2 describe-target-groups elbv2 describe-target-groups
  for tg in $(jq -r '.TargetGroups[].TargetGroupArn' "$base/$r/elbv2/describe-target-groups.json"); do
    "$C" "$r" elbv2/target-health "${tg##*/}" elbv2 describe-target-health --target-group-arn "$tg"
  done
  "$C" "$r" elb describe-load-balancers elb describe-load-balancers
  "$C" "$r" rds describe-db-instances rds describe-db-instances
  "$C" "$r" rds describe-db-clusters rds describe-db-clusters
  "$C" "$r" rds describe-db-snapshots rds describe-db-snapshots --snapshot-type manual
  "$C" "$r" rds describe-db-cluster-snapshots rds describe-db-cluster-snapshots --snapshot-type manual
  "$C" "$r" sagemaker list-endpoints sagemaker list-endpoints
  "$C" "$r" sagemaker list-notebook-instances sagemaker list-notebook-instances
  "$C" "$r" sagemaker list-domains sagemaker list-domains
  "$C" "$r" sagemaker list-apps sagemaker list-apps
  "$C" "$r" eks list-clusters eks list-clusters
  for c in $(jq -r '.clusters[]' "$base/$r/eks/list-clusters.json"); do
    "$C" "$r" eks/cluster "$c" eks describe-cluster --name "$c"
    "$C" "$r" eks/nodegroups "$c" eks list-nodegroups --cluster-name "$c"
  done
  arns=$(jq -r '.clusterArns[]' "$base/$r/ecs/list-clusters.json" | tr '\n' ' ')
  # describe-clusters は 1 回 100 本まで
  [ -n "$arns" ] && "$C" "$r" ecs describe-clusters ecs describe-clusters --clusters $arns
  "$C" "$r" logs describe-log-groups logs describe-log-groups
  "$C" "$r" ecr describe-repositories ecr describe-repositories
  for repo in $(jq -r '.repositories[].repositoryName' "$base/$r/ecr/describe-repositories.json"); do
    "$C" "$r" ecr/images "${repo//\//__}" ecr describe-images --repository-name "$repo" --query 'imageDetails[].{t:imageTags,p:imagePushedAt,pull:lastRecordedPullTime,sz:imageSizeInBytes}'
    sleep 0.2
  done
done
