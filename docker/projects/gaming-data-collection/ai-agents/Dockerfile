FROM pytorch/pytorch:2.4.0-cuda12.4-cudnn9-devel

ARG DEBIAN_FRONTEND=noninteractive

# 1) Node.js 24 をインストール（NodeSource を利用）
#    あわせて openssh-client (ssh/scp/ssh-keygen) も導入
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gnupg openssh-client \
  && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
  && apt-get update && apt-get install -y --no-install-recommends nodejs \
  && rm -rf /var/lib/apt/lists/*

# 2) uv を Astral の公式イメージからコピー（インストールが安定）
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

# 3) 動作確認（任意）
RUN python --version && pip --version && node --version && uv --version \
  && ssh -V && scp -V 2>&1 | head -1 && ssh-keygen -? 2>&1 | head -1

# 共通の依存関係をインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    pkg-config \
    libxml2-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libncurses5-dev \
    libgdbm-dev \
    wget \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*
