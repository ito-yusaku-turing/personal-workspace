# 開発用 Docker コンテナ
# Node.js 24, PHP 5.4/7.3/8.5, Ruby 3.4, Python 3.14
# MySQL Client 8.4.8, PostgreSQL Client 17.7

FROM node:24.13.0-bookworm AS base

# 共通の依存関係をインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    autoconf \
    automake \
    libtool \
    bison \
    re2c \
    pkg-config \
    libxml2-dev \
    libsqlite3-dev \
    libcurl4-openssl-dev \
    libonig-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libzip-dev \
    libssl-dev \
    libreadline-dev \
    zlib1g-dev \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libncurses5-dev \
    libgdbm-dev \
    libyaml-dev \
    libgmp-dev \
    wget \
    curl \
    git \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# Ruby 3.4.7 ビルド
# ============================================================
FROM base AS ruby-builder

WORKDIR /tmp

# Ruby 3.4.7 ダウンロードとビルド
RUN wget -q https://cache.ruby-lang.org/pub/ruby/3.4/ruby-3.4.7.tar.gz \
    && tar xzf ruby-3.4.7.tar.gz \
    && cd ruby-3.4.7 \
    && ./configure \
        --prefix=/usr/local/ruby \
        --enable-shared \
        --disable-install-doc \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/ruby-3.4.7*

# ============================================================
# Python 3.14.2 ビルド
# ============================================================
FROM base AS python-builder

WORKDIR /tmp

# Python 3.14.2 ダウンロードとビルド
RUN wget -q https://www.python.org/ftp/python/3.14.2/Python-3.14.2.tar.xz \
    && tar xJf Python-3.14.2.tar.xz \
    && cd Python-3.14.2 \
    && ./configure \
        --prefix=/usr/local/python \
        --enable-optimizations \
        --enable-shared \
        --with-ensurepip=install \
        LDFLAGS="-Wl,-rpath,/usr/local/python/lib" \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/Python-3.14.2*

# ============================================================
# 最終イメージ
# ============================================================
FROM node:24.13.0-bookworm-slim

# ランタイム依存関係をインストール
RUN apt-get update && apt-get install -y --no-install-recommends \
    libxml2 \
    libsqlite3-0 \
    libcurl4 \
    libonig5 \
    libpng16-16 \
    libjpeg62-turbo \
    libfreetype6 \
    libzip4 \
    libssl3 \
    libreadline8 \
    zlib1g \
    libbz2-1.0 \
    libffi8 \
    liblzma5 \
    libncurses6 \
    libgdbm6 \
    libyaml-0-2 \
    libgmp10 \
    git \
    curl \
    wget \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ============================================================
# MySQL Client 8.4.8 インストール (直接debパッケージ)
# ============================================================
RUN wget -q https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-common_8.4.8-1debian12_amd64.deb \
    && wget -q https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-community-client-plugins_8.4.8-1debian12_amd64.deb \
    && wget -q https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-community-client-core_8.4.8-1debian12_amd64.deb \
    && wget -q https://dev.mysql.com/get/Downloads/MySQL-8.4/mysql-community-client_8.4.8-1debian12_amd64.deb \
    && dpkg -i mysql-common_8.4.8-1debian12_amd64.deb \
    && dpkg -i mysql-community-client-plugins_8.4.8-1debian12_amd64.deb \
    && dpkg -i mysql-community-client-core_8.4.8-1debian12_amd64.deb \
    && dpkg -i mysql-community-client_8.4.8-1debian12_amd64.deb \
    && rm -f mysql-*.deb

# ============================================================
# PostgreSQL Client 17.7 インストール
# ============================================================
RUN echo "deb http://apt.postgresql.org/pub/repos/apt bookworm-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && wget -qO - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

# Ruby をコピー
COPY --from=ruby-builder /usr/local/ruby /usr/local/ruby

# Python をコピー
COPY --from=python-builder /usr/local/python /usr/local/python

# シンボリックリンクを作成
RUN ln -s /usr/local/ruby/bin/ruby /usr/local/bin/ruby \
    && ln -s /usr/local/ruby/bin/gem /usr/local/bin/gem \
    && ln -s /usr/local/ruby/bin/bundle /usr/local/bin/bundle \
    && ln -s /usr/local/ruby/bin/irb /usr/local/bin/irb \
    && ln -s /usr/local/python/bin/python3 /usr/local/bin/python3 \
    && ln -s /usr/local/python/bin/python3 /usr/local/bin/python \
    && ln -s /usr/local/python/bin/pip3 /usr/local/bin/pip3 \
    && ln -s /usr/local/python/bin/pip3 /usr/local/bin/pip

# Python共有ライブラリのパスを設定
ENV LD_LIBRARY_PATH="/usr/local/python/lib"

# デフォルトの作業ディレクトリ
WORKDIR /workspace

# バージョン確認用のヘルスチェック
RUN echo "=== Installed Versions ===" \
    && echo "Node.js: $(node --version)" \
    && echo "npm: $(npm --version)" \
    && echo "Ruby: $(ruby --version)" \
    && echo "Python: $(python --version)" \
    && echo "MySQL Client: $(mysql --version)" \
    && echo "PostgreSQL Client: $(psql --version)"

# Codexのためによく使うコマンド一式を入れる
RUN apt-get update && apt-get install -y --no-install-recommends \
    ripgrep jq fd-find unzip zip make lsof netcat-openbsd tree less vim-tiny \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/bash"]
