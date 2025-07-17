# Julia在庫管理システム - Docker Image
FROM julia:1.10-slim

# メタデータ
LABEL maintainer="Julia在庫管理システム開発チーム"
LABEL description="高性能で安全な日本語対応在庫管理システム"
LABEL version="1.0.0"

# 環境変数
ENV JULIA_PROJECT=/app
ENV JULIA_DEPOT_PATH=/opt/julia
ENV INVENTORY_PORT=8000
ENV INVENTORY_ENV=production

# 必要なシステムパッケージをインストール
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# アプリケーション用ユーザーを作成
RUN groupadd -r inventory && useradd -r -g inventory inventory

# アプリケーションディレクトリを作成
WORKDIR /app

# 必要なディレクトリを作成
RUN mkdir -p data logs backups && \
    chown -R inventory:inventory /app

# 依存関係ファイルをコピー
COPY Project.toml Manifest.toml ./

# Julia依存関係をインストール
RUN julia --project=. -e "using Pkg; Pkg.instantiate(); Pkg.precompile()"

# アプリケーションファイルをコピー
COPY --chown=inventory:inventory src/ ./src/
COPY --chown=inventory:inventory docs/ ./docs/
COPY --chown=inventory:inventory test/ ./test/
COPY --chown=inventory:inventory *.md ./

# ヘルスチェック用スクリプトを作成
RUN echo '#!/bin/bash\necho "Checking Julia inventory system health..."\ncurl -f http://localhost:${INVENTORY_PORT}/api/health || exit 1' > /usr/local/bin/healthcheck.sh && \
    chmod +x /usr/local/bin/healthcheck.sh

# アプリケーションユーザーに切り替え
USER inventory

# アプリケーションをプリコンパイル
RUN julia --project=. -e "include(\"src/InventorySystem.jl\"); using .InventorySystem"

# ポートを公開
EXPOSE 8000

# ヘルスチェック
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD /usr/local/bin/healthcheck.sh

# 起動スクリプト
CMD ["julia", "--project=.", "-e", "include(\"src/InventorySystem.jl\"); using .InventorySystem; start_server(parse(Int, get(ENV, \"INVENTORY_PORT\", \"8000\")))"]

# Docker Compose用の設定例をコメントで提供
# 
# version: '3.8'
# services:
#   inventory-system:
#     build: .
#     ports:
#       - "8000:8000"
#     environment:
#       - INVENTORY_PORT=8000
#       - INVENTORY_ENV=production
#       - JWT_SECRET=your-super-secret-jwt-key
#       - DB_PATH=/app/data/inventory.db
#     volumes:
#       - inventory_data:/app/data
#       - inventory_logs:/app/logs
#       - inventory_backups:/app/backups
#     restart: unless-stopped
#     healthcheck:
#       test: ["CMD", "/usr/local/bin/healthcheck.sh"]
#       interval: 30s
#       timeout: 10s
#       retries: 3
#       start_period: 40s
# 
# volumes:
#   inventory_data:
#   inventory_logs:
#   inventory_backups: