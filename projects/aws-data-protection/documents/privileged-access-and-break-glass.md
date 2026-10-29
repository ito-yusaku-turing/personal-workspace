# 特権アクセスと break-glass の一般論（学習用）

作成: 2026-10-29 ／ 伊藤（下書きはエージェント）

大きな企業や、セキュリティの要件が厳しい組織が、強い権限（特権）を持つ人をどう設計・管理しているかをまとめた学習用の資料です。規格と、クラウド事業者の公式のガイドを根拠にしています（2026-10-29 に原典で確認。確認できなかったものは、その旨を書いています）。

当社に当てはめた案は、別の資料にしました: [BreakGlass の設計（叩き台）](../workstream/s3-data-protection-2/breakglass-design-draft.md)。

## 要点

- 特権の管理は、技術だけでなく、**組織と人の仕組み**で支えます。柱は「職務の分離」「最小の権限と、必要なときだけの権限」「人のライフサイクルの管理」「緊急用のアクセスを別に持つこと」の 4 つです。
- **「特権の昇格」と「緊急用のアクセス（本来の break-glass）」は別物です。** 昇格はふだんの入口（IdP）から強い権限を一時的に得ること、緊急用は IdP などが止まったときにも入れる別の入口のことです。
- 特権を持つ人には、資格（誰がなれるか）、認証（フィッシングに強い MFA・専用の ID や端末）、使うときの規律（理由を残す・通知される・自分で自分を監査しない）、定期的な見直しと訓練が求められます。
- どの資料も、**予防しきれない分は、記録と通知で補う**という考え方で一貫しています。

## 1. 用語

| 用語 | 意味 |
|---|---|
| 特権（privileged access） | システムの設定・権限・ログなど、セキュリティに関わる操作ができる権限。管理者権限 |
| 最小の権限（least privilege） | 職務に必要な権限だけを与えること（NIST SP 800-53 AC-6） |
| 職務の分離（separation / segregation of duties） | 1 人で不正や誤りを完結できないよう、職務を分けること（AC-5、ISO/IEC 27001 A.5.3） |
| 特権の昇格、Just-In-Time（JIT） | 普段は強い権限を持たず、必要なときに期限付きで得ること。申請・承認・期限・記録を伴うのが典型。製品の分類では特権アクセス管理（PAM） |
| 緊急用のアクセス（emergency access、break-glass） | 通常の入口（IdP・SSO など）が使えない緊急時に、それでも入るための経路。ガラスを割って非常ボタンを押すことにたとえた呼び名 |
| accounts of last resort | ネットワークが使えないときなどに使う、まれにしか使わないローカルのアカウント。NIST は緊急用・一時用のアカウントと混同しないよう注意している（AC-2 の解説） |
| 二人制（two-person control、dual authorization） | 少なくとも 2 人の許可を得た人がそろわないと、操作できない仕組み（NIST の用語集。SP 800-53 では AC-3(2)・CM-5(4) など） |
| 鍵の分割（split knowledge） | 秘密の情報を分割し、1 人だけでは中身が分からないようにすること。元は暗号の鍵の用語（NIST SP 800-57） |

## 2. 組織と人のレイヤーの設計

### 2.1 職務の分離

「権限を使う人」「権限を与える人」「使ったことを見張る人」を別にします。

- **アクセス権を職務として定め、文書にします**（NIST AC-5）。
- **監査のログを管理できる人を、特権を持つ人のうちの一部に限ります**（AU-9(4)）。理由は、監査される側の特権者がログを改ざんしうるためです。
  - AWS では、ログを別のアカウント（ログアーカイブ）に置き、ワークロードの管理者が触れない形にするのが定石です。
- 政府統一基準のガイドライン（7.1.3）も、**権限を付与する人と、権限を執行する人を分ける**ことを基本の対策に挙げています。
- IPA の内部不正防止ガイドラインは、管理者が 1 人しかいないときは、**管理者以外の人が操作の履歴を確かめる**よう求めています。

### 2.2 最小の権限と、必要なときだけの権限

- **特権のアカウントを、決めた人とロールに限ります**（AC-6(5)）。
- **特権を持つ人も、ふだんの作業では特権の無いアカウントを使います**（AC-6(2)）。政府統一基準（8.1.1）も「管理者権限の ID は、管理者としての業務を行うときだけ使う」としています。
- **特に強い権限は常に与えず、必要なときに有効化します。** 政府統一基準のガイドライン（7.1.3 の解説）は、都度の申請と承認を経て執行し、作業後は確実に外すことを書いています。
- クラウドでの実現手段:
  - AWS は、IAM Identity Center と提携先の製品（CyberArk・Okta Access Requests など）の連携、または自分で動かすサンプル（TEAM）を案内しています。2026-10 時点で、Identity Center そのものに JIT の機能は見当たりません。
  - Google Cloud には、公式の JIT（Privileged Access Manager）があります。
- **承認を挟むかどうかは組織によります。** 申請と承認を必須にする方式のほかに、理由の記録と通知で代える方式もあります。

### 2.3 人のライフサイクルの管理

- **入社・異動・退職に合わせて、権限を付け外しします**（AC-2 の (l)。特権のロールの割り当てと変更の監視は AC-2(7)）。
- **権限を定期的に見直します**（AC-6(7)、政府統一基準 7.1.3）。特権は、ふつうの権限より短い周期で見直すのが一般的です。
- **特権を持つ人には、アクセスの前に条件を課します。**
  - 人員の審査（PS-3、ISO A.6.1）。
  - アクセスの合意書への署名（PS-6、ISO A.6.2）。
  - 役割に応じた教育（AT-3、ISO A.6.3）。
- 一時用・緊急用のアカウントは、決めた期間が過ぎたら自動で削除または無効にします（AC-2(2)）。

### 2.4 緊急用のアクセスを別に持つ

通常の入口が止まったときの経路を、**通常の入口に依存しない形で**事前に用意します（3 章）。

## 3. 緊急用のアクセス（本来の break-glass）

### 3.1 Microsoft のガイド（Entra ID の緊急アクセス用アカウント）

この分野の代表的な指針です。

- **数:** 2 つ以上。
- **独立性:** クラウド専用のアカウントにします。社内のディレクトリと同期せず、外部の IdP とも連携しません。
- **アクセスの条件:** サインインを制限するポリシー（条件付きアクセス）から除外し、制限の設定を誤っても入れるようにします。
- **認証:** パスワードを使わない、フィッシングに強い方式（パスキー（FIDO2）、証明書）を使います。ふだんの管理者のアカウントとは別の方式にします。
- **保管:** 認証の情報を特定の個人に結び付けず、耐火の金庫に分けて保管します。金庫の番号は、定期的にと、担当者が辞めたときに変えます。
- **監視:** 使われるたびに、最も重大な扱いのアラートを出します。使った後は振り返りをして、訓練か、本当の緊急か、悪用かを判定します。
- **検証:** 少なくとも 90 日ごとと、担当者の異動・退職のときに、実際にサインインできるか、アラートが鳴るか、手順書が使えるかを確かめます。

### 3.2 AWS のガイド

- **Well-Architected の SEC03-BP03「緊急アクセスの手順を定める」**
  - 障害の種類ごとに手順を決めます。例えば、IdP が止まった、IdP と AWS の連携の設定が壊れた、IAM Identity Center が止まった、などです。
  - 緊急用のアカウント・IAM ユーザー・ロールは、事前に作っておきます。
  - 承認・ログ・アラートを用意します。ガイドは、緊急の手順は「裏口」とみなせると書いています。
  - 平常に戻ったら、認証の情報を作り直します。
  - 演習（game day）で試します。
  - **避けるべき形として、緊急の手順が、通常と同じ IdP に依存していることを挙げています。**
- **IAM Identity Center の「緊急アクセスの設定」:** Identity Center やリージョンが止まっても、外部の IdP から IAM へ直接連携して入れる構成を、障害の前に作り、試しておくよう案内しています。
- **ホワイトペーパー「複数のアカウントで AWS 環境を構成する」の break-glass の節**
  - 緊急用の IAM ユーザーは 2 人以上とし、ハードウェアの MFA を付けます。
  - パスワードと MFA のキーは別の人が持ちます。つまり、使うには 2 人が要ります。
  - 置き場所は管理アカウントを推奨しています。Well-Architected の「緊急用の専用アカウント」とは、推奨が少しずれます。
- **root の一元管理**
  - AWS Organizations のメンバーのアカウントの root について、認証の情報を消せます。
  - root でしかできない一部の作業は、管理アカウントから `sts:AssumeRoot` で、作業を絞った短いセッション（例: 900 秒）で行います。対象は、S3・SQS の全拒否のポリシーの削除と、root の認証の情報の監査・削除・再作成だけです。**アカウントの中で何でもできる入口ではありません。**
  - root そのものが要るときは、パスワードの回復を許可し、root のメールを受け取れる人がパスワードを設定し直します。作業の後は、認証の情報を再び消します。
  - 注意（原典ではなく推論）: 緊急用のアカウントの root まで消すと、Well-Architected の「緊急用のアカウントの root で入る」案は使えなくなります。

### 3.3 昇格と緊急用の関係

両者を正面から並べて定義した公式の資料は見つかりませんでした。ただ、各社の資料は、両者を区別する立場で書かれています。

- Microsoft は、緊急用のアカウントを、昇格の仕組み（PIM）の対象にせず、常に有効にしておくよう求めています。昇格の仕組みが使えないとき（承認者がいないなど）の最後の手段という位置付けです。
- AWS の JIT のページは、事業継続のために緊急用のアクセスを別に用意するよう勧めています。
- 例外として、Google Cloud の JIT は「緊急時のアクセス（承認を待たない昇格）」を用途に含めています。ただし、Google も別に緊急用のアカウントを計画するよう勧めています。

## 4. 特権を持つ人に課される要件

上の資料に共通する要件を、4 つに分けて並べます。

### 4.1 資格（誰がなれるか）

| 要件 | 根拠 |
|---|---|
| 職務上の必要がある人に限る。人数は最小限だが、緊急用は 2 人以上 | AC-6(5)、Microsoft・AWS のガイド |
| 割り当てる前に審査する（身元・経歴など。どこまで行うかは国と組織による） | PS-3、ISO A.6.1 |
| アクセスの合意書・利用規程に署名する | PS-6、ISO A.6.2 |
| 役割に応じた教育を、割り当ての前と定期的に受ける | AT-3、ISO A.6.3 |

### 4.2 認証と端末

| 要件 | 根拠 |
|---|---|
| 特権のアカウントには MFA を必須にする | NIST IA-2(1)、政府統一基準のガイドライン |
| MFA はフィッシングに強い方式（FIDO2 など）にする | Microsoft のガイド |
| ふだんの ID と特権の ID を分ける | AC-6(2)、政府統一基準 8.1.1 |
| 管理の作業には専用の端末（PAW）を使う | Microsoft のガイド、政府統一基準のガイドライン |
| 認証の情報を共有しない。なくしたらすぐに報告する | 一般的な運用 |

### 4.3 使うときの規律

| 要件 | 根拠 |
|---|---|
| 特権の操作をログに残す | AC-6(9)、IPA |
| 使ったら通知・アラートが届き、本人以外が確かめる | Microsoft・AWS のガイド、IPA |
| 自分の操作を自分で監査しない。ログを管理できる人を分ける | AU-9(4)、AC-5 |
| 特に危険な操作は二人制にする（必要に応じて） | AC-3(2)、CM-5(4)。政府統一基準のガイドラインの「デュアルロック」、IPA |
| 一時的に得た権限は、作業の後に確実に外す | 政府統一基準のガイドライン、AC-2(2) |

### 4.4 見直しと訓練

| 要件 | 根拠 |
|---|---|
| 権限の必要性を定期的に見直す | AC-6(7)、政府統一基準 7.1.3 |
| 異動・退職のときにすぐ外す | AC-2 |
| 緊急用の経路を定期的に試す（Microsoft は 90 日ごと） | Microsoft・AWS のガイド |

## 5. 組織の規模に合わせて選ぶ

大きな企業では、上の要件のほぼすべてを、PAM の製品・専任のセキュリティのチーム・内部監査で回しています。小さな組織が全部を持ち込むと、運用が回らずに形骸化します。どの資料にも共通する、外しにくい核は次のとおりです。

1. 特権を持つ人を絞り、ふだんは使わない。
2. 特権の利用は、フィッシングに強い MFA でだけ行う。
3. 使ったら、必ず本人以外に分かる（記録と通知）。ログは使った本人の手が届かない場所に置く。
4. 通常の入口が止まったときの経路を、通常の入口とは別に用意し、定期的に試す。
5. 名簿を定期的に見直す。

承認の流れ、PAM の製品、専用の端末、身元の審査などは、脅威の大きさと人手に応じて足していくものです。

## 確認の状況

- ISO/IEC 27001:2022 の附属書 A の番号と名前は、二次資料（ISMS.online など）でだけ確かめました。ISO と JIS の原文では照合していません。
- FISC の安全対策基準は有料のため、特権 ID への言及を原文で確かめていません。
- 日本語の訳語は、規格の公式の訳ではなく、この資料での言い換えです。

## 参考文献

- NIST SP 800-53 Rev.5（Release 5.2.0）— https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final （OSCAL 版: https://github.com/usnistgov/oscal-content/tree/main/nist.gov/SP800-53/rev5 ）
- NIST Glossary「two-person control」— https://csrc.nist.gov/glossary/term/two_person_control
- NIST Glossary「dual authorization」— https://csrc.nist.gov/glossary/term/dual_authorization
- NIST Glossary「split knowledge」— https://csrc.nist.gov/glossary/term/split_knowledge
- ISO/IEC 27001:2022 — https://www.iso.org/standard/27001
- （二次資料）ISMS.online「ISO 27001:2022 Annex A 8.2」— https://www.isms.online/iso-27001/annex-a-2022/8-2-use-of-privileged-access-rights-2022/
- Microsoft Learn「Manage emergency access admin accounts」— https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access
- AWS Well-Architected SEC03-BP03「Establish emergency access process」— https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/sec_permissions_emergency_process.html
- AWS DevOps Guidance AG.SAD.5「Implement break-glass procedures」— https://docs.aws.amazon.com/wellarchitected/latest/devops-guidance/ag.sad.5-implement-break-glass-procedures.html
- AWS Whitepaper「Organizing Your AWS Environment Using Multiple Accounts — Break glass access」— https://docs.aws.amazon.com/whitepapers/latest/organizing-your-aws-environment/break-glass-access.html
- AWS IAM Identity Center「Set up emergency access to the AWS Management Console」— https://docs.aws.amazon.com/singlesignon/latest/userguide/emergency-access.html
- AWS IAM「AWS account root user」— https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user.html
- AWS IAM「Perform a privileged task on an AWS Organizations member account」— https://docs.aws.amazon.com/IAM/latest/UserGuide/id_root-user-privileged-task.html
- AWS IAM Identity Center「Temporary elevated access for AWS accounts」— https://docs.aws.amazon.com/singlesignon/latest/userguide/temporary-elevated-access.html
- AWS Security Blog「Temporary elevated access management with IAM Identity Center」（2023-06-08）— https://aws.amazon.com/blogs/security/temporary-elevated-access-management-with-iam-identity-center/
- TEAM（aws-samples）— https://github.com/aws-samples/iam-identity-center-team
- Google Cloud「Privileged Access Manager overview」— https://docs.cloud.google.com/iam/docs/pam-overview
- Google Cloud「Operations best practices」（Plan breakglass access）— https://docs.cloud.google.com/architecture/blueprints/security-foundations/operation-best-practices
- 国家サイバー統括室「政府統一基準群」（令和7年度版）— https://www.cyber.go.jp/policy/group/general/kijun.html （統一基準: https://www.cyber.go.jp/pdf/policy/general/kijyunr7.pdf 、ガイドライン: https://www.cyber.go.jp/pdf/policy/general/guider8_6_02.pdf ）
- IPA「組織における内部不正防止ガイドライン」第5版 — https://www.ipa.go.jp/security/guide/insider.html
- FISC「金融機関等コンピュータシステムの安全対策基準・解説書」（有料。本文は未確認）— https://www.fisc.or.jp/
