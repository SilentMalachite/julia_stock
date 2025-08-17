# Julia在庫管理システム 運用マニュアル

## 目次

1. [システム概要](#システム概要)
2. [インストールとセットアップ](#インストールとセットアップ)
3. [日常運用](#日常運用)
4. [監視とメンテナンス](#監視とメンテナンス)
5. [バックアップと復旧](#バックアップと復旧)
6. [トラブルシューティング](#トラブルシューティング)
7. [セキュリティ運用](#セキュリティ運用)
8. [パフォーマンス最適化](#パフォーマンス最適化)

---

注意: 本マニュアルの一部（定期メンテナンスや監視スクリプト例など）は参考実装です。リポジトリに含まれないスクリプト名が登場する箇所は、運用環境に合わせて作成してください（同等の手順は手動でも実施可能です）。

## システム概要

### アーキテクチャ

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Webブラウザ   │───→│  Genie Web API   │───→│   DuckDB        │
│   (クライアント) │    │  (Julia Server)  │    │  (データベース)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │   Excel Files    │
                       │ (インポート/エクスポート)│
                       └──────────────────┘
```

### 主要コンポーネント

- **Julia アプリケーション**: メインビジネスロジック
- **DuckDB**: 高性能データベースエンジン
- **Genie フレームワーク**: Web API サーバー
- **認証システム**: JWT ベース認証
- **ログシステム**: 構造化ログとセキュリティ監査

---

## インストールとセットアップ

### 前提条件

- **Julia**: 1.9以上
- **OS**: Linux, macOS, Windows
- **メモリ**: 最低2GB、推奨8GB
- **ディスク**: 最低10GB、推奨50GB

### 初回セットアップ

#### 1. ソースコードの配置

```bash
git clone https://github.com/SilentMalachite/julia_stock.git
cd julia_stock
```

#### 2. 依存関係のインストール

```bash
julia --project=. -e "using Pkg; Pkg.instantiate()"
```

#### 3. ディレクトリ構造の確認

```bash
mkdir -p data logs backups
chmod 755 data logs backups
```

#### 4. 環境変数の設定

本システムは一部の設定を環境変数から読み込みます。最低限、以下を設定してください。

```bash
# JWT（必須）
export JWT_SECRET="change-me-to-a-strong-secret"   # 16文字以上推奨

# デフォルト管理者の自動作成（任意・強度チェックあり）
export ADMIN_DEFAULT_PASSWORD="YourStrongAdminPass!23"
export ADMIN_DEFAULT_EMAIL="admin@company.com"

# パスワードハッシュのストレッチ回数（任意・既定: 10000, 下限: 1000）
export PASSWORD_HASH_ITERATIONS=10000
```

注: `.env` ファイルの自動読み込みは現状行っていません。必要に応じてプロセスマネージャやシェル起動スクリプトで変数を読み込んでください。

#### 5. データベースの初期化

```bash
julia --project=. scripts/init_db.jl
```

#### 6. 管理者アカウントの作成

```bash
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
init_auth_database();
admin = create_user(\"admin\", \"AdminPass123!\", \"admin@company.com\", \"admin\");
println(\"管理者アカウントが作成されました: \", admin.username)
"
```

#### 7. サービスの起動確認

```bash
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
start_server(8000)
"
```

---

## 日常運用

### サービス起動

#### 手動起動

```bash
cd /path/to/julia_stock
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
start_server()
" > logs/server.log 2>&1 &
```

#### systemdサービス（Linux）

`/etc/systemd/system/inventory-system.service`:

```ini
[Unit]
Description=Julia Inventory Management System
After=network.target

[Service]
Type=simple
User=inventory
Group=inventory
WorkingDirectory=/opt/julia_stock
ExecStart=/usr/local/bin/julia --project=. -e "include(\"src/InventorySystem.jl\"); using .InventorySystem; start_server()"
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

サービスの有効化と起動：

```bash
sudo systemctl enable inventory-system
sudo systemctl start inventory-system
sudo systemctl status inventory-system
```

### 定期メンテナンスタスク

#### 日次タスク

```bash
#!/bin/bash
# /opt/julia_stock/scripts/daily_maintenance.sh

# ログローテーション
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
cleanup_old_logs(7)  # 7日以上古いログを削除
"

# データベース統計更新
julia --project=. scripts/update_stats.jl

# バックアップ
./scripts/backup.sh
```

crontabに登録：

```bash
0 2 * * * /opt/julia_stock/scripts/daily_maintenance.sh
```

#### 週次タスク

```bash
#!/bin/bash
# scripts/weekly_maintenance.sh

# データベース最適化
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
conn = get_connection_from_pool();
DuckDB.execute(conn, \"VACUUM\");
return_connection_to_pool(conn);
"

# 古いセッションのクリーンアップ
julia --project=. scripts/cleanup_sessions.jl

# セキュリティログの分析
julia --project=. scripts/security_analysis.jl
```

---

## 監視とメンテナンス

### ヘルスチェック

#### サービス状態確認

```bash
# プロセス確認
ps aux | grep julia

# ポート確認
netstat -tlnp | grep :8000

# API レスポンス確認
curl -f http://localhost:8000/api/health || echo "API not responding"
```

#### システムリソース監視

```bash
#!/bin/bash
# scripts/health_check.sh

# CPU使用率
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')

# メモリ使用率
MEM_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')

# ディスク使用率
DISK_USAGE=$(df -h /opt/julia_stock | awk 'NR==2 {print $5}' | sed 's/%//')

# データベースサイズ
DB_SIZE=$(du -sh data/inventory.db | cut -f1)

echo "CPU: ${CPU_USAGE}%, Memory: ${MEM_USAGE}%, Disk: ${DISK_USAGE}%, DB: ${DB_SIZE}"

# アラート条件
if (( $(echo "$CPU_USAGE > 80" | bc -l) )); then
    echo "ALERT: High CPU usage: ${CPU_USAGE}%"
fi

if (( $(echo "$MEM_USAGE > 80" | bc -l) )); then
    echo "ALERT: High memory usage: ${MEM_USAGE}%"
fi

if [ "$DISK_USAGE" -gt 80 ]; then
    echo "ALERT: High disk usage: ${DISK_USAGE}%"
fi
```

### ログ監視

#### 重要なログパターン

```bash
# エラーログの監視
tail -f logs/error.log | grep -E "(ERROR|FATAL)"

# セキュリティイベントの監視
tail -f logs/security.log | grep -E "(failed_login_attempt|connection_leak_detected)"

# パフォーマンス警告
tail -f logs/app.log | grep -E "(high_usage|timeout)"
```

#### ログ分析スクリプト

```julia
# scripts/log_analysis.jl
using JSON3, Dates

function analyze_logs(log_file::String, hours::Int = 24)
    cutoff_time = now() - Hour(hours)
    errors = []
    warnings = []
    
    open(log_file, "r") do io
        for line in eachline(io)
            try
                log_entry = JSON3.read(line)
                timestamp = DateTime(log_entry.timestamp)
                
                if timestamp > cutoff_time
                    if log_entry.level == "ERROR"
                        push!(errors, log_entry)
                    elseif log_entry.level == "WARNING"
                        push!(warnings, log_entry)
                    end
                end
            catch
                continue
            end
        end
    end
    
    println("過去 $hours 時間のログ分析:")
    println("エラー数: $(length(errors))")
    println("警告数: $(length(warnings))")
    
    return errors, warnings
end

errors, warnings = analyze_logs("logs/app.log")
```

---

## バックアップと復旧

### バックアップ戦略

#### データベースバックアップ

```bash
#!/bin/bash
# scripts/backup.sh

BACKUP_DIR="/opt/backups/julia_stock"
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_PATH="$BACKUP_DIR/backup_$DATE"

mkdir -p "$BACKUP_PATH"

# データベースファイルのコピー
cp data/inventory.db "$BACKUP_PATH/"
cp data/auth.db "$BACKUP_PATH/"

# 設定ファイルのバックアップ
cp .env "$BACKUP_PATH/"
cp -r scripts "$BACKUP_PATH/"

# ログファイルのバックアップ（最新のみ）
cp logs/app.log "$BACKUP_PATH/"
cp logs/security.log "$BACKUP_PATH/"

# 圧縮
cd "$BACKUP_DIR"
tar -czf "backup_$DATE.tar.gz" "backup_$DATE"
rm -rf "backup_$DATE"

# 古いバックアップの削除（30日以上古い）
find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +30 -delete

echo "バックアップ完了: backup_$DATE.tar.gz"
```

#### リアルタイムバックアップ（推奨）

```bash
# scripts/continuous_backup.sh
#!/bin/bash

# rsyncを使った差分バックアップ
rsync -av --delete data/ /backup/julia_stock/data/
rsync -av --delete logs/ /backup/julia_stock/logs/

# データベースのホットバックアップ
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
conn = get_connection_from_pool();
DuckDB.execute(conn, \"COPY (SELECT * FROM stocks) TO '/backup/julia_stock/stocks_backup.csv' (HEADER, DELIMITER ',')\");
return_connection_to_pool(conn);
"
```

### 復旧手順

#### データベース復旧

```bash
#!/bin/bash
# scripts/restore.sh

BACKUP_FILE=$1
if [ -z "$BACKUP_FILE" ]; then
    echo "使用法: $0 <backup_file.tar.gz>"
    exit 1
fi

# サービス停止
sudo systemctl stop inventory-system

# バックアップの展開
cd /opt/backups/julia_stock
tar -xzf "$BACKUP_FILE"
BACKUP_DIR=$(basename "$BACKUP_FILE" .tar.gz)

# データベースファイルの復元
cp "$BACKUP_DIR/inventory.db" /opt/julia_stock/data/
cp "$BACKUP_DIR/auth.db" /opt/julia_stock/data/

# 権限の修正
chown -R inventory:inventory /opt/julia_stock/data/

# サービス再起動
sudo systemctl start inventory-system

echo "復旧完了"
```

#### 部分復旧（在庫データのみ）

```julia
# scripts/restore_stocks.jl
using CSV, DataFrames

function restore_stocks_from_csv(csv_file::String)
    # CSVファイルからデータを読み込み
    df = CSV.read(csv_file, DataFrame)
    
    # データベース接続
    conn = get_connection_from_pool()
    
    try
        # 既存データの削除（注意！）
        secure_execute(conn, "DELETE FROM stocks")
        
        # データの復元
        for row in eachrow(df)
            stock = Stock(
                row.id, row.name, row.code, row.quantity, row.unit,
                row.price, row.category, row.location, 
                DateTime(row.created_at), DateTime(row.updated_at)
            )
            secure_insert_stock(conn, stock)
        end
        
        println("復元完了: $(nrow(df))件")
        
    finally
        return_connection_to_pool(conn)
    end
end

# 使用例
restore_stocks_from_csv("/backup/julia_stock/stocks_backup.csv")
```

---

## トラブルシューティング

### 一般的な問題と解決策

#### 1. サービスが起動しない

**症状**: アプリケーションが起動しない

**確認項目**:
```bash
# ポートの使用状況
sudo lsof -i :8000

# Julia パッケージの状態
julia --project=. -e "using Pkg; Pkg.status()"

# ログファイルの確認
tail -n 50 logs/error.log
```

**解決策**:
```bash
# パッケージの再インストール
julia --project=. -e "using Pkg; Pkg.resolve(); Pkg.instantiate()"

# ポートの変更（必要に応じて）
# .env ファイルで SERVER_PORT を変更
```

#### 2. データベース接続エラー

**症状**: "データベース接続に失敗しました"

**確認項目**:
```bash
# データベースファイルの存在確認
ls -la data/inventory.db data/auth.db

# ファイル権限の確認
stat data/inventory.db

# ディスク容量の確認
df -h
```

**解決策**:
```bash
# 権限の修正
chmod 644 data/*.db

# データベースの再作成
julia --project=. scripts/init_db.jl

# 接続プールのリセット
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
recover_connection_pool()
"
```

#### 3. 認証エラー

**症状**: "JWT token が無効です"

**確認項目**:
```bash
# 認証データベースの確認
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
init_auth_database();
println(\"認証DB初期化完了\")
"

# JWT 秘密鍵の確認
grep JWT_SECRET .env
```

**解決策**:
```bash
# 認証データベースの初期化
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
init_auth_database();
"

# 管理者アカウントの再作成
julia --project=. scripts/create_admin.jl
```

#### 4. パフォーマンス問題

**症状**: レスポンスが遅い

**診断**:
```bash
# システムリソースの確認
top
iostat 1
free -h

# データベースサイズの確認
du -sh data/

# ログの確認
grep -E "(timeout|slow)" logs/app.log
```

**解決策**:
```julia
# データベース最適化
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
conn = get_connection_from_pool();
DuckDB.execute(conn, \"VACUUM\");
DuckDB.execute(conn, \"ANALYZE\");
return_connection_to_pool(conn);
"

# 接続プールサイズの調整
# .env ファイルで DB_POOL_MAX_CONNECTIONS を増加
```

### 緊急時対応

#### サービス復旧優先順位

1. **レベル1** (5分以内): サービス再起動
```bash
sudo systemctl restart inventory-system
```

2. **レベル2** (15分以内): 設定リセット
```bash
cp config/default.env .env
sudo systemctl restart inventory-system
```

3. **レベル3** (30分以内): データベース復旧
```bash
scripts/restore.sh latest_backup.tar.gz
```

4. **レベル4** (1時間以内): 完全な再構築
```bash
scripts/full_restore.sh
```

---

## セキュリティ運用

### 日常的なセキュリティチェック

#### 1. ログ監視

```bash
# 不審なログイン試行の確認
grep "failed_login_attempt" logs/security.log | tail -20

# 大量リクエストの検出
grep -c "$(date '+%Y-%m-%d')" logs/app.log

# SQL インジェクション攻撃の検出
grep -E "(DROP|UNION|SELECT.*FROM)" logs/security.log
```

#### 2. ユーザーアカウント監査

```julia
# scripts/security_audit.jl
using Dates

function security_audit()
    # 全ユーザーの取得
    users = get_all_users()
    
    for user in users
        # 最終ログイン時間のチェック
        if user.last_login < now() - Day(90)
            println("警告: ユーザー $(user.username) が90日間ログインしていません")
        end
        
        # 権限の確認
        if user.role == "admin" && user.created_at > now() - Day(7)
            println("注意: 新しい管理者アカウント: $(user.username)")
        end
    end
end

security_audit()
```

#### 3. アクセス制御

```bash
# 不要なポートのクローズ確認
nmap localhost

# ファイアウォール設定確認
sudo ufw status

# SSL証明書の有効期限確認（本番環境）
openssl x509 -in /path/to/cert.pem -noout -dates
```

### セキュリティインシデント対応

#### 1. 不正アクセス検出時

```bash
#!/bin/bash
# scripts/security_incident.sh

# 該当IPアドレスをブロック
IP_ADDRESS=$1
sudo ufw deny from "$IP_ADDRESS"

# セキュリティログの詳細分析
grep "$IP_ADDRESS" logs/security.log > "incident_$(date +%Y%m%d_%H%M%S).log"

# 管理者への通知
echo "セキュリティインシデント検出: $IP_ADDRESS" | mail -s "Security Alert" admin@company.com

# 関連セッションの無効化
julia --project=. -e "
include(\"src/InventorySystem.jl\");
using .InventorySystem;
invalidate_sessions_by_ip(\"$IP_ADDRESS\")
"
```

#### 2. データ漏洩対応

```bash
# 即座にサービス停止
sudo systemctl stop inventory-system

# ネットワーク切断
sudo ufw --force enable
sudo ufw default deny incoming
sudo ufw default deny outgoing

# ログの保全
cp -r logs/ /secure/incident_logs/$(date +%Y%m%d_%H%M%S)/

# データベースのスナップショット作成
cp data/*.db /secure/incident_data/$(date +%Y%m%d_%H%M%S)/
```

---

## パフォーマンス最適化

### 監視指標

#### システムメトリクス

```bash
# scripts/performance_monitor.sh
#!/bin/bash

# CPU使用率
echo "CPU Usage:"
mpstat 1 5 | awk 'END{print "Average: " 100-$NF "%"}'

# メモリ使用率
echo "Memory Usage:"
free | awk 'NR==2{printf "%.2f%%\n", $3*100/$2}'

# I/O 統計
echo "Disk I/O:"
iostat -x 1 5 | awk 'END{print "Average util: " $NF "%"}'

# ネットワーク統計
echo "Network:"
sar -n DEV 1 5 | grep Average | grep -v lo
```

#### アプリケーションメトリクス

```julia
# scripts/app_metrics.jl
function collect_metrics()
    # データベース接続プール統計
    pool_stats = get_pool_statistics()
    println("接続プール使用率: $(pool_stats[:usage_rate] * 100)%")
    
    # API レスポンス時間（ログから抽出）
    response_times = extract_response_times_from_logs()
    avg_response_time = sum(response_times) / length(response_times)
    println("平均レスポンス時間: $(avg_response_time)ms")
    
    # エラー率
    error_count = count_errors_last_hour()
    total_requests = count_requests_last_hour()
    error_rate = error_count / total_requests * 100
    println("エラー率: $(error_rate)%")
end

collect_metrics()
```

### 最適化手法

#### 1. データベース最適化

```sql
-- インデックスの作成
CREATE INDEX idx_stocks_category ON stocks(category);
CREATE INDEX idx_stocks_code ON stocks(code);
CREATE INDEX idx_stocks_updated_at ON stocks(updated_at);

-- 統計情報の更新
ANALYZE;

-- テーブルの最適化
VACUUM;
```

#### 2. 接続プール調整

```julia
# config/performance_tuning.jl
# 高負荷環境用設定
init_connection_pool(
    max_connections = 50,
    min_connections = 10,
    connection_timeout = 60,
    idle_timeout = 300,
    health_check_interval = 30
)
```

#### 3. メモリ最適化

```julia
# ガベージコレクションの調整
ENV["JULIA_GC_ALLOC_SYNCED"] = "1"
ENV["JULIA_GC_POOL_DELAYED"] = "0"

# プリコンパイルの活用
using PackageCompiler
create_sysimage(["Genie", "DuckDB", "JSON3"], sysimage_path="inventory_system.so")
```

