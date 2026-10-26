# 原本バケットを壊せる主体の一覧（2026-10-20 時点）

- 生成: `data/final.py`（IAM ポリシーシミュレーター＋プレフィックスで絞った Allow の静的走査）。手で直さず、取り直すときは再生成する
- 範囲: tuscenes-prod（767397804933）の IAM ロール 686・ユーザー 38。対象は親の 12 本。SCP は反映していない（シミュレーターが見ない）
- 「12」は 12 本すべて。calibration(旧) は `tuscenes-calibration`、calibration(新) は `tuscenes-calibration-767397804933`。`tu-` は `tuscenes-`
- 最終利用: ロールは `RoleLastUsed`、ユーザーは本文の表を参照

| 主体 | できる操作（対象バケット） | プレフィックスの限定 | 最終利用 | 引き受け元 |
|---|---|---|---|---|
| `role/AWSControlTowerExecution` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2025-09-12 | 210332786925:root |
| `role/aws-controltower-AdministratorExecutionRole` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | — | 494249021538:role/aws-controltower-AuditAdministratorRole |
| `role/cdk-hnb659fds-cfn-exec-role-767397804933-ap-northeast-1` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-10-15 | cloudformation |
| `role/cdk-hnb659fds-cfn-exec-role-767397804933-us-east-1` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-01-27 | cloudformation |
| `role/cdk-hnb659fds-cfn-exec-role-767397804933-us-east-2` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2025-07-15 | cloudformation |
| `role/cdk-hnb659fds-cfn-exec-role-767397804933-us-west-2` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-10-20 | cloudformation |
| `role/ecsTaskExecutionRole` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2025-03-25 | ecs-tasks |
| `role/service-role/AmazonEMRStudio_RuntimeRole` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2024-08-28 | emr-serverless |
| `role/service-role/CodeCatalystWorkflowDevelopmentRole-tuscenes-prod` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2024-03-14 | codecatalyst<br>codecatalyst-runner |
| `role/service-role/tuscenes-sampler-test-role-n1huu9jg` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2024-07-10 | lambda |
| `role/sfn-auto-labeling-AwsBatchPreprocessFunctionService-fn3Nf1jGLQTc` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2024-10-11 | lambda |
| `role/skypilot-v1` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-08-14 | ec2 |
| `role/stacksets-exec-ff6bf58b4ea65bd878839a71faebc74a` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-02-02 | 210332786925:role/aws-service-role/stacksets.cloudformation/AWSServiceRoleForCloudFormationStackSetsOrgAdmin |
| `role/tuscenes-processing` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2024-07-16 | ec2 |
| `sso/AWSReservedSSO_AWSAdministratorAccess_619c2f8a913e315a` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | 2026-10-19 | 767397804933 |
| `sso/AWSReservedSSO_FullAccess_ed608317ee39a850` | 版の削除（calibration(新)・calibration(旧)・denso-nx-raw・denso-raw・denso-taxi-processed・denso-taxi-video・gaming-data-collection・td1-rlog・tu-annotation・tu-model）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（calibration(新)・calibration(旧)・denso-nx-raw・denso-raw・denso-taxi-processed・denso-taxi-video・gaming-data-collection・td1-rlog・tu-annotation・tu-model）、上書き（12） |  | 2026-10-20 | 767397804933 |
| `sso/AWSReservedSSO_TeamE2E_87b32d413e7af329` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（calibration(新)・calibration(旧)・denso-nx-raw・denso-raw・denso-taxi-processed・denso-taxi-video・gaming-data-collection・td1-rlog・tu-annotation・tu-model）、上書き（calibration(新)・calibration(旧)・denso-nx-raw・denso-raw・denso-taxi-processed・denso-taxi-video・gaming-data-collection・td1-rlog・tu-annotation・tu-model） |  | 2026-10-20 | 767397804933 |
| `user/jadd-datasync` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | — |  |
| `user/jadd-remote-sync-kohei.watanabe` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | — |  |
| `user/jadd_studio_amplify` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | — |  |
| `user/shio-secretsmanager_GetSecretValue` | 版の削除（12）、バージョニング（12）、ライフサイクル（12）、ポリシー（12）、ポリシー削除（12）、Object Lock（12）、バケット削除（12）、削除（12）、上書き（12） |  | — |  |
| `user/tokyo30-dataupload-pc-01` | 版の削除（td1-raw・td1-rlog・tu-raw）、バージョニング（td1-raw・td1-rlog・tu-raw）、ライフサイクル（td1-raw・td1-rlog・tu-raw）、Object Lock（td1-raw・td1-rlog・tu-raw）、バケット削除（td1-raw・td1-rlog・tu-raw）、削除（td1-raw・td1-rlog・tu-raw）、上書き（td1-raw・td1-rlog・tu-raw） |  | — |  |
| `role/BackendApi-BackendApiBackendApiHandlerServiceRole36-U2mAFH1GhWbG` | 版の削除（tu-model）、削除（tu-model）、上書き（calibration(新)・tu-model） | `tuscenes-calibration-…/calibration_results/*` | 2026-10-20 | lambda |
| `role/DensoNx-ExtractorJobRole12098145-t9PUpx6T64wG` | 版の削除（td1-raw）、削除（td1-raw）、上書き（td1-raw） |  | 2026-10-02 | ecs-tasks |
| `role/ModelConverter-EgpuModelConverterSfnModelConverterT-EO2AB7nPDtCZ` | 版の削除（tu-model）、削除（tu-model）、上書き（tu-model） | `tuscenes-model-…/fullcombo/**` | 2026-10-16 | ecs-tasks |
| `role/ModelConverter-ModelConverterSfnModelConverterTaskD-yCGjcQxCWBXn` | 版の削除（tu-model）、削除（tu-model）、上書き（tu-model） | `tuscenes-model-…/fullcombo/**` | 2026-10-20 | ecs-tasks |
| `role/ModelcoreBuild-TaskRole30FC0FBB-xYjuPsSIn1et` | 版の削除（tu-model）、削除（tu-model）、上書き（tu-model） |  | 2026-10-20 | ecs-tasks |
| `role/databricks-s3-ingest-20363-db_s3_iam` | ライフサイクル（tu-raw）、削除（tu-raw）、上書き（tu-raw） |  | 2026-10-19 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-20363-db_s3_iam |
| `role/databricks-s3-ingest-25d30-db_s3_iam` | ライフサイクル（tu-annotation）、削除（tu-annotation）、上書き（tu-annotation） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-25d30-db_s3_iam |
| `role/databricks-s3-ingest-3090e-db_s3_iam` | ライフサイクル（td1-raw）、削除（td1-raw）、上書き（td1-raw） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-3090e-db_s3_iam |
| `role/databricks-s3-ingest-3ecc9-db_s3_iam` | ライフサイクル（tu-model）、削除（tu-model）、上書き（tu-model） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-3ecc9-db_s3_iam |
| `role/databricks-s3-ingest-782bc-db_s3_iam` | ライフサイクル（denso-taxi-processed）、削除（denso-taxi-processed）、上書き（denso-taxi-processed） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-782bc-db_s3_iam |
| `role/databricks-s3-ingest-90299-db_s3_iam` | ライフサイクル（calibration(新)）、削除（calibration(新)）、上書き（calibration(新)） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-90299-db_s3_iam |
| `role/databricks-s3-ingest-9bf18-db_s3_iam` | ライフサイクル（denso-raw）、削除（denso-raw）、上書き（denso-raw） |  | 2026-10-09 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-9bf18-db_s3_iam |
| `role/databricks-s3-ingest-d9a0f-db_s3_iam` | ライフサイクル（gaming-data-collection）、削除（gaming-data-collection）、上書き（gaming-data-collection） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-d9a0f-db_s3_iam |
| `role/databricks-s3-ingest-denso-nx-raw-767397804933-db_s3_iam` | ライフサイクル（denso-nx-raw）、削除（denso-nx-raw）、上書き（denso-nx-raw） |  | 2026-10-20 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-denso-nx-raw-767397804933-db_s3_iam |
| `role/databricks-s3-ingest-fb5a6-db_s3_iam` | ライフサイクル（td1-rlog）、削除（td1-rlog）、上書き（td1-rlog） |  | 2026-10-09 | 414351767826:role/unity-catalog-prod-UCMasterRole-14S5ZJVKOTYTL<br>767397804933:role/databricks-s3-ingest-fb5a6-db_s3_iam |
| `role/Coder-WorkspaceRole736431E1-QNn6za9CHBGQ` | 削除（12）、上書き（12） |  | 2026-10-20 | ec2 |
| `role/CoderWorkspace-ClusterWorkspaceRoleCB6131B7-soWYRnYcQ7Vo` | 削除（12）、上書き（12） |  | — | pods.eks |
| `role/CoderWorkspace-ClusterWorkspaceRoleCB6131B7-vGvHsN3RkavH` | 削除（12）、上書き（12） |  | 2025-02-26 | pods.eks |
| `role/CoderWorkspaceRole` | 削除（12）、上書き（12） |  | 2025-10-08 | ec2 |
| `role/DensoNx-AzureDataSyncTaskS3AccessRole79A67816-KKtOwwv6ohQX` | 削除（denso-nx-raw）、上書き（denso-nx-raw） | `denso-nx-raw-…/azure-mlops1/dcorp-inbound/*` | 2026-10-19 | datasync |
| `role/DensoTaxiStack-AzureDataSyncGeniac4TaskS3AccessRole-RM4A0yMSQ1xo` | 削除（denso-taxi-processed）、上書き（denso-taxi-processed） |  | 2026-09-23 | datasync |
| `role/DensoTaxiStack-AzureDataSyncGeniac4VideoTaskS3Acces-q2fveLPD5iZe` | 削除（denso-taxi-video）、上書き（denso-taxi-video） |  | 2026-09-23 | datasync |
| `role/DensoTaxiStack-AzureDataSyncTaskS3AccessRole79A6781-RJdZqYMLle5i` | 削除（denso-taxi-processed）、上書き（denso-taxi-processed） |  | 2026-08-05 | datasync |
| `role/DensoTaxiStack-AzureDataSyncVideoTaskS3AccessRole54-RTCoLpLsKCUO` | 削除（denso-taxi-video）、上書き（denso-taxi-video） |  | 2026-08-05 | datasync |
| `role/GlueRole` | 削除（12）、上書き（12） | `*/*aws-glue-*/*` | 2024-08-28 | glue |
| `role/PerceptionDetection-BatchJobRole8F5EADCB-0ejEyW9bmAZx` | 削除（tu-annotation）、上書き（tu-annotation） | `tuscenes-annotation-…/object_detection/auto_label/0.1.0/*` | 2026-10-20 | ecs-tasks |
| `role/service-role/AmazonSageMaker-ExecutionRole-20240315T103566` | 削除（12）、上書き（12） |  | 2024-04-01 | sagemaker |
| `role/service-role/SageMaker-ExecutionRole-20240206T192166` | 削除（calibration(新)・calibration(旧)・tu-annotation・tu-model・tu-raw）、上書き（calibration(新)・calibration(旧)・tu-annotation・tu-model・tu-raw） |  | 2024-05-07 | sagemaker |
| `sso/AWSReservedSSO_GamingDataCollection_9adea50411ddd80c` | 削除（gaming-data-collection）、上書き（gaming-data-collection） |  | 2026-08-30 | 767397804933 |
| `sso/AWSReservedSSO_JADDViewer_0467b1be8aab6820` | 削除（12）、上書き（12） |  | 2026-04-02 | 767397804933 |
| `sso/AWSReservedSSO_TeamDataPlanning_444d280ac21a7bf4` | 削除（calibration(新)）、上書き（calibration(新)） |  | 2025-12-21 | 767397804933 |
| `sso/AWSReservedSSO_TeamFundamentalAI_e4d4f9bb5ff5d3da` | 削除（tu-model）、上書き（tu-model） |  | 2026-10-20 | 767397804933 |
| `role/Datalake-RlogDecoderFunctionServiceRole3490568D-5khAyjjQtMUm` | 上書き（td1-raw） |  | 2026-10-20 | lambda |
| `role/LidarDeleter` | 削除（td1-raw・tu-raw） | `td1-raw-…/*/lidar/*`<br>`tuscenes-raw-…/*/lidar/*` | 2026-09-03 | 767397804933:role/aws-reserved/sso/us-west-2/AWSReservedSSO_FullAccess_ed608317ee39a850 |
| `role/PerceptionDetection-LambdasPlanJobsServiceRoleF843E-61eCQWrhW0iC` | 上書き（tu-annotation） | `tuscenes-annotation-…/object_detection/auto_label/0.1.0/*` | 2026-10-20 | lambda |
| `role/PerceptionDetection-LaneBatchJobRoleF578B392-hRSyGHW0N507` | 上書き（tu-annotation） | `tuscenes-annotation-…/lane_master_kun/auto_label/v0.3.0/*` | 2026-10-20 | ecs-tasks |
| `role/PerceptionDetection-LaneLambdasPlanJobsServiceRoleB-UI8qBfenvEAz` | 上書き（tu-annotation） | `tuscenes-annotation-…/lane_master_kun/auto_label/v0.3.0/*` | 2026-10-20 | lambda |
| `role/S3BatchDeleteLidar` | 削除（td1-raw・tu-raw） | `td1-raw-…/*/lidar/*`<br>`tuscenes-raw-…/*/lidar/*` | — | batchoperations.s3 |
| `role/SkypilotApiServer-ApiServerRole23EFC621-Js44pHrEGokd` | 上書き（calibration(新)・calibration(旧)・tu-annotation・tu-model・tu-raw） |  | 2026-10-19 | pods.eks |
| `role/Train3dGs-Train3dGsBatchJobRoleD8E342C8-LvarjhHVu7AE` | 上書き（tu-model） |  | 2026-10-16 | ecs-tasks |
| `sso/AWSReservedSSO_TeamDrivingSoftware_23a1540096234650` | 上書き（12） |  | 2026-10-20 | 767397804933 |
| `user/gaggle-shared-user` | 上書き（tu-model） | `tuscenes-model-…/bevfusion/*` | — |  |
| `user/gaming-data-collection-uploader` | 上書き（gaming-data-collection） |  | — |  |
| `user/tsukamoto` | 上書き（td1-raw） |  | — |  |
