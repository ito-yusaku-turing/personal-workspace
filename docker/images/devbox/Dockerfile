# syntax=docker/dockerfile:1
#
# devbox — 開発用イメージ
#
# 開発サーバー（app サービス）とコーディングエージェント（devbox サービス）の双方で
# この1イメージを使う。ランタイムのバージョンを揃えることで、同じリポジトリの
# ビルドキャッシュ（.next 等）を異なるランタイムで触って壊す事故を防ぐ。
#
# 常に入るもの:
#   - Node.js（CI / デプロイと同一バージョン。バージョンの正はリポジトリの .nvmrc）
#   - git / git-lfs / OpenSSH クライアント / GitHub CLI (gh)
#   - ripgrep / jq / fd / tree 等、コーディングエージェントが常用するコマンド
#   - build-essential + python3（ネイティブアドオンを node-gyp でビルドするため）
#
# 任意（docker/config/project.conf の DEVBOX_WITH_* で切り替える。既定はすべて 0）:
#   - PostgreSQL クライアント / AWS CLI v2 / Google Cloud CLI / Databricks CLI / uv
#
# 認証情報はイメージに焼かない。コンテナ HOME へのマウント経由で持ち込む。

# ------------------------------------------------------------------------------------
# ベースイメージ
#   NODE_VERSION の正はリポジトリ直下の .nvmrc。compose 経由のビルドでは
#   docker/bin/lib/common.sh が .nvmrc を読んで渡すため、下の既定値は素の
#   `docker build` を叩いたときだけのフォールバック。
# ------------------------------------------------------------------------------------
ARG NODE_VERSION=24.22.1
FROM node:${NODE_VERSION}-bookworm-slim

# ------------------------------------------------------------------------------------
# プロジェクト固有の値（docker/config/project.conf から渡る）
#   コンテナ内のスクリプトはこれらを /etc/devbox.conf 経由で読む。
#   ハードコードしないことで、テンプレートを別プロジェクトへそのまま持ち込める。
# ------------------------------------------------------------------------------------
ARG PROJECT_NAME=project
ARG CONTAINER_REPO_DIR=/usr/app/project
ARG PERSONAL_CONFIG_DIR_NAME=.project
ARG TZ=Asia/Tokyo

# ------------------------------------------------------------------------------------
# 同梱ツールの選択（1 で有効）
# ------------------------------------------------------------------------------------
ARG DEVBOX_WITH_PSQL=0
ARG DEVBOX_WITH_AWS=0
ARG DEVBOX_WITH_GCLOUD=0
ARG DEVBOX_WITH_DATABRICKS=0
ARG DEVBOX_WITH_UV=0

# 各ツールのバージョン（PG_MAJOR 以外は固定版を落としてくる）
ARG PG_MAJOR=17
ARG GH_VERSION=2.96.0
ARG DATABRICKS_VERSION=1.9.0
ARG GCLOUD_VERSION=581.0.0
ARG UV_VERSION=0.13.4

# イメージの契約バージョン。entrypoint の挙動や /etc/devbox.conf のような
# スクリプトが依存する要素を変えたら、この値と docker/bin/lib/common.sh の
# DEVBOX_IMAGE_SCHEMA を一緒に +1 する。ホスト側スクリプトが両者を突き合わせ、
# 古いイメージのまま実行しようとしたら再ビルドを促す。
LABEL devbox.schema="1"

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8
ENV TZ=${TZ}

# ------------------------------------------------------------------------------------
# 基本パッケージ
# ------------------------------------------------------------------------------------
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl wget gnupg \
        git git-lfs openssh-client \
        build-essential python3 python3-venv \
        ripgrep jq fd-find unzip zip make lsof netcat-openbsd tree less vim-tiny procps; \
    ln -sf "$(command -v fdfind)" /usr/local/bin/fd; \
    # LFS の smudge/clean フィルタを全ユーザーに設定する。HOME はマウントで
    # 持ち込まれるため、イメージに焼くには --system である必要がある
    git lfs install --system --skip-repo; \
    rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------------------------------
# GitHub CLI
#   GitHub 認証セットアップ（docker/container-bin/setup/github.sh）が使うため常に入れる
# ------------------------------------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    curl -fsSLo /tmp/gh.deb \
      "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${arch}.deb"; \
    dpkg -i /tmp/gh.deb; \
    rm -f /tmp/gh.deb

# ------------------------------------------------------------------------------------
# PostgreSQL クライアント（任意 / pgdg リポジトリ）
# ------------------------------------------------------------------------------------
RUN set -eux; \
    if [ "$DEVBOX_WITH_PSQL" = "1" ]; then \
      curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc \
        | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg; \
      echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" \
        > /etc/apt/sources.list.d/pgdg.list; \
      apt-get update; \
      apt-get install -y --no-install-recommends "postgresql-client-${PG_MAJOR}"; \
      rm -rf /var/lib/apt/lists/*; \
    fi

# ------------------------------------------------------------------------------------
# AWS CLI v2（任意）
# ------------------------------------------------------------------------------------
RUN set -eux; \
    if [ "$DEVBOX_WITH_AWS" = "1" ]; then \
      case "$(dpkg --print-architecture)" in \
        amd64) aws_arch=x86_64 ;; \
        arm64) aws_arch=aarch64 ;; \
        *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
      esac; \
      curl -fsSLo /tmp/awscliv2.zip "https://awscli.amazonaws.com/awscli-exe-linux-${aws_arch}.zip"; \
      unzip -q /tmp/awscliv2.zip -d /tmp; \
      /tmp/aws/install; \
      rm -rf /tmp/aws /tmp/awscliv2.zip; \
    fi

# ------------------------------------------------------------------------------------
# Databricks CLI（任意）
# ------------------------------------------------------------------------------------
RUN set -eux; \
    if [ "$DEVBOX_WITH_DATABRICKS" = "1" ]; then \
      arch="$(dpkg --print-architecture)"; \
      curl -fsSLo /tmp/databricks.zip \
        "https://github.com/databricks/cli/releases/download/v${DATABRICKS_VERSION}/databricks_cli_${DATABRICKS_VERSION}_linux_${arch}.zip"; \
      unzip -q /tmp/databricks.zip -d /tmp/databricks; \
      install -m 0755 /tmp/databricks/databricks /usr/local/bin/databricks; \
      rm -rf /tmp/databricks /tmp/databricks.zip; \
    fi

# ------------------------------------------------------------------------------------
# Google Cloud CLI（任意）
#
#   バンドル版 Python は使わない。base に python3 があり、二重に持つと 100MB 以上増えるため
#   CLOUDSDK_PYTHON で明示する（未指定だと gcloud が python を自力で探して環境差が出る）。
# ------------------------------------------------------------------------------------
ENV CLOUDSDK_PYTHON=/usr/bin/python3
RUN set -eux; \
    if [ "$DEVBOX_WITH_GCLOUD" = "1" ]; then \
      case "$(dpkg --print-architecture)" in \
        amd64) gcloud_arch=x86_64 ;; \
        arm64) gcloud_arch=arm ;; \
        *) echo "unsupported architecture: $(dpkg --print-architecture)" >&2; exit 1 ;; \
      esac; \
      curl -fsSLo /tmp/gcloud.tar.gz \
        "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-${gcloud_arch}.tar.gz"; \
      tar -xzf /tmp/gcloud.tar.gz -C /usr/local; \
      rm -f /tmp/gcloud.tar.gz; \
      /usr/local/google-cloud-sdk/install.sh --quiet \
        --usage-reporting=false --path-update=false --command-completion=false; \
      ln -sf /usr/local/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud; \
      ln -sf /usr/local/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil; \
      # 使わないものを落としてイメージを小さく保つ。components で入れ直せる
      rm -rf /usr/local/google-cloud-sdk/.install/.backup \
             /usr/local/google-cloud-sdk/platform/bundledpythonunix; \
      gcloud --version; \
    fi

# ------------------------------------------------------------------------------------
# uv（任意 / Python ツールチェーン）
# ------------------------------------------------------------------------------------
RUN set -eux; \
    if [ "$DEVBOX_WITH_UV" = "1" ]; then \
      UV_INSTALL_DIR=/usr/local/bin INSTALLER_NO_MODIFY_PATH=1 \
        sh -c "curl -fsSL https://astral.sh/uv/${UV_VERSION}/install.sh | sh"; \
    fi

# ------------------------------------------------------------------------------------
# 実行時設定
#   - コンテナは root で起動し、entrypoint がホストの UID/GID（HOST_UID / HOST_GID）に
#     降格する。降格前に passwd エントリの home を /usr/home に揃えるため、
#     ssh のように getpwuid() を見るコマンドでも ~/.ssh が正しく解決される。
#   - npm のグローバル導入先を HOME 配下にし、非 root でも claude / codex を
#     入れられる & コンテナを作り直しても消えないようにする。
# ------------------------------------------------------------------------------------
ENV HOME=/usr/home \
    NPM_CONFIG_PREFIX=/usr/home/.local \
    NPM_CONFIG_UPDATE_NOTIFIER=false \
    PATH=/usr/home/.local/bin:$PATH

# UID とファイル所有者が一致しないホスト（Docker Desktop 等）でも git が動くようにする
RUN git config --system --add safe.directory '*'

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod 0755 /usr/local/bin/docker-entrypoint.sh

# ------------------------------------------------------------------------------------
# /etc/devbox.conf — devbox コンテナの中であることの目印 兼 コンテナ内設定
#
#   docker/container-bin/ のスクリプトは「これが無ければホストなので実行しない」、
#   docker/bin/ のスクリプトは「これがあればコンテナ内なので実行しない」と判定する。
#   加えて、プロジェクト名・リポジトリのマウント先・同梱ツールの構成を書いておき、
#   コンテナ内のスクリプトがそれを読む（ハードコードしないため）。
# ------------------------------------------------------------------------------------
RUN set -eux; \
    { \
      echo "# devbox コンテナのビルド時設定（生成物 / 編集しない）"; \
      echo "DEVBOX_SCHEMA=1"; \
      echo "DEVBOX_PROJECT_NAME=${PROJECT_NAME}"; \
      echo "DEVBOX_REPO_DIR=${CONTAINER_REPO_DIR}"; \
      echo "DEVBOX_PERSONAL_CONFIG_DIR_NAME=${PERSONAL_CONFIG_DIR_NAME}"; \
      echo "DEVBOX_TZ=${TZ}"; \
      echo "DEVBOX_WITH_PSQL=${DEVBOX_WITH_PSQL}"; \
      echo "DEVBOX_WITH_AWS=${DEVBOX_WITH_AWS}"; \
      echo "DEVBOX_WITH_GCLOUD=${DEVBOX_WITH_GCLOUD}"; \
      echo "DEVBOX_WITH_DATABRICKS=${DEVBOX_WITH_DATABRICKS}"; \
      echo "DEVBOX_WITH_UV=${DEVBOX_WITH_UV}"; \
    } > /etc/devbox.conf

WORKDIR ${CONTAINER_REPO_DIR}

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["bash"]
