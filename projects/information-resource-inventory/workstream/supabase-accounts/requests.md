# Supabase の見直しの依頼文（下書き）

[アクションプラン](../supabase-accounts.md#アクションプラン)で使う依頼文の下書き。`<...>` は送る前に埋める。

## 1. メンバー全員へ（ヒアリングと MFA の予告）

対象: Supabase の組織のメンバー全員（伊藤を除く 19 名）。

> Supabase の組織（会社契約の Pro）のメンバーを見直しています。2 点お願いします。
>
> **1. いまも Supabase のダッシュボードを使っているか教えてください（<回答期限> まで）**
> - 使っている場合: どのプロジェクトを使っているか（例: jadd-studio-prod、drivers-app-dev）
> - 使っていない場合: 組織から外します。外れてもアプリ（JADD STUDIO など）へのログインには影響しません。必要になったら、また招待します。
>
> **2. MFA を設定してください（<MFA 必須化の日> まで）**
> <MFA 必須化の日> に、組織で MFA を必須にします。設定していない人は、その日から組織のプロジェクトを開けなくなります（MFA を設定すれば戻ります）。
> - 設定の場所: ダッシュボード右上のアカウント → Account preferences → Security → Multi-factor authentication
> - Supabase にはリカバリーコードがありません。認証アプリを 2 つの端末に登録しておいてください（すべて失うとアカウントを戻せません）。
> - Personal Access Token を作っている人は、使っていないものを消してください。

## 2. 山本さんへ（MFA の必須化と、Owner の扱い）

> Supabase の組織（`dhazyhuzuwitqasezcvr`）のメンバーを見直しています。SSO は Team プラン（+$574/月）が必要なので見送り、MFA の必須化と、使っていない人を外すことで進めます。
>
> MFA の必須化は Owner しか設定できず、いま MFA を設定している Owner は山本さんだけなので、お願いさせてください。
>
> **お願い 1: <MFA 必須化の日> に MFA を必須にする**
> - 場所: Organization settings → Security → 「Require MFA to access organization」をオン
> - 設定していないメンバーは、その日から組織のプロジェクトを開けなくなります（メンバーからは外れず、MFA を設定すれば戻ります）。
> - 前日に、MFA を設定していない人の一覧をお送りします。
>
> **お願い 2: Owner のお二人（安本さん・渡辺さん）に、MFA の設定を声かけしてほしい**
> - 必須化すると、MFA を設定していない Owner も組織に入れなくなります。
>
> **お願い 3（必要になったら）: Owner の見直し**
> - Owner の追加・削除は Owner にしかできません。ヒアリングで Owner が要らない人がいれば、Developer か Administrator への変更をお願いします。
>
> 補足: Developer と Administrator を外すのは、伊藤（Administrator）が行います。
