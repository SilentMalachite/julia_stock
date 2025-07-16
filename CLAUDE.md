# Julia在庫管理システム

このプロジェクトは、Julia言語、DuckDB、Genieを使用して構築された日本語対応の在庫管理システムです。ローカル環境とクラウド環境の両方で動作し、Excelファイルとの連携機能を提供します。

## プロジェクト概要

### 主要機能
- 在庫データの管理（追加、更新、削除、検索）
- Excelファイルからのデータインポート・エクスポート
- Webインターフェースによるデータアクセス
- 日本語での完全サポート
- ローカル・クラウド環境対応

### 技術スタック
- **Julia**: メイン開発言語
- **DuckDB**: 高速データベースエンジン
- **Genie.jl**: Webアプリケーションフレームワーク
- **XLSX.jl**: Excelファイル操作
- **DataFrames.jl**: データ操作

## 開発環境セットアップ

### 前提条件
- Julia 1.9以上
- Git

### セットアップ手順

1. **Juliaパッケージの初期化**
   ```bash
   julia --project=. -e "using Pkg; Pkg.instantiate()"
   ```

2. **開発サーバーの起動**
   ```bash
   julia --project=. -e "using Genie; Genie.loadapp(); up()"
   ```

3. **データベースの初期化**
   ```bash
   julia --project=. scripts/init_db.jl
   ```

## プロジェクト構造

```
julia_stock/
├── Project.toml              # Julia依存関係
├── src/
│   ├── InventorySystem.jl    # メインモジュール
│   ├── models/
│   │   └── Stock.jl          # 在庫データモデル
│   ├── database/
│   │   └── DuckDBConnection.jl  # データベース接続
│   ├── excel/
│   │   └── ExcelHandler.jl   # Excel操作
│   └── web/
│       ├── routes.jl         # Webルート
│       └── controllers/
├── public/                   # 静的ファイル
├── views/                    # HTMLテンプレート
├── data/                     # データファイル
├── scripts/                  # ユーティリティスクリプト
└── test/                     # テストファイル
```

## 主要コマンド

### セットアップ（初回のみ）
```bash
# 依存関係をインストール
julia --project=. -e "using Pkg; Pkg.instantiate()"

# データベースを初期化
julia --project=. scripts/init_db.jl

# 追加サンプルデータを挿入（オプション）
julia --project=. scripts/insert_sample_data.jl
```

### 開発
```bash
# 開発サーバー起動
julia --project=. -e "include(\"src/InventorySystem.jl\"); InventorySystem.start_server()"

# テスト実行（TDD）
julia --project=. test/runtests.jl

# パッケージ更新
julia --project=. -e "using Pkg; Pkg.update()"
```

### データベース操作
```bash
# データベース初期化
julia --project=. scripts/init_db.jl

# サンプルデータ挿入
julia --project=. scripts/insert_sample_data.jl

# データベースバックアップ
julia --project=. scripts/backup_db.jl
```

### Excel操作
```bash
# Excelからインポート
julia --project=. -e "include(\"src/excel/ExcelHandler.jl\"); ExcelHandler.import_from_excel(\"data/inventory.xlsx\")"

# Excelへエクスポート
julia --project=. -e "include(\"src/excel/ExcelHandler.jl\"); ExcelHandler.export_to_excel(\"output/inventory_export.xlsx\")"
```

## API エンドポイント

### 在庫管理
- `GET /api/stocks` - 全在庫一覧取得
- `GET /api/stocks/:id` - 特定在庫取得
- `POST /api/stocks` - 新規在庫追加
- `PUT /api/stocks/:id` - 在庫更新
- `DELETE /api/stocks/:id` - 在庫削除

### Excel連携
- `POST /api/excel/import` - Excelファイルインポート
- `GET /api/excel/export` - Excelファイルエクスポート

## トラブルシューティング

### よくある問題
1. **Julia環境の問題**: `julia --project=. -e "using Pkg; Pkg.resolve()"`でパッケージ競合を解決
2. **DuckDB接続エラー**: データベースファイルの権限を確認
3. **Genie起動失敗**: ポート8000が使用中でないか確認

### ログ確認
- アプリケーションログ: `logs/app.log`
- データベースログ: `logs/database.log`
- エラーログ: `logs/error.log`

## デプロイ

### ローカル環境
```bash
julia --project=. -e "include(\"src/InventorySystem.jl\"); InventorySystem.start_server(8000)"
```

### クラウド環境（Heroku例）
```bash
# Procfile作成
echo "web: julia --project=. -e \"include(\\\"src/InventorySystem.jl\\\"); InventorySystem.start_server(parse(Int, ENV[\\\"PORT\\\"]))]\"" > Procfile

# デプロイ
git push heroku main
```

## 開発ガイドライン

### コーディング規則
- Julia標準のスタイルガイドに従う
- 関数・変数名は英語（コメントは日本語可）
- 型安定性を重視
- ドキュメント文字列を必須とする

### テスト
- 新機能には必ずテストを作成
- カバレッジ80%以上を維持
- CI/CDパイプラインでの自動テスト実行