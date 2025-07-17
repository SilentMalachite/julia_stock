# Julia在庫管理システム

[![CI](https://github.com/SilentMalachite/julia_stock/actions/workflows/ci.yml/badge.svg)](https://github.com/SilentMalachite/julia_stock/actions/workflows/ci.yml)
[![Deploy](https://github.com/SilentMalachite/julia_stock/actions/workflows/deploy.yml/badge.svg)](https://github.com/SilentMalachite/julia_stock/actions/workflows/deploy.yml)
[![CodeQL](https://github.com/SilentMalachite/julia_stock/actions/workflows/codeql.yml/badge.svg)](https://github.com/SilentMalachite/julia_stock/actions/workflows/codeql.yml)
[![Julia](https://img.shields.io/badge/Julia-1.9+-9558B2?style=flat&logo=julia&logoColor=white)](https://julialang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![DuckDB](https://img.shields.io/badge/DuckDB-0.9+-FFF000?style=flat&logo=duckdb&logoColor=black)](https://duckdb.org/)
[![Genie](https://img.shields.io/badge/Genie-5.0+-E24A33?style=flat)](https://genieframework.com/)

日本語対応在庫管理システム。Julia言語とDuckDBを使用。まだアルファ版です。

## 🎉 新機能: モダンGUI

よりユーザーフレンドリーなモダンGUIを実装しました！
- 📊 リアルタイムダッシュボード
- 🔍 高度な検索・フィルター機能
- 📱 レスポンシブデザイン
- ⚡ リアルタイム更新
- 📤 Excel連携の強化

詳細は[モダンGUIガイド](docs/MODERN_GUI_GUIDE.md)をご覧ください。

![システム概要](docs/assets/system-overview.png)

## ✨ 主な機能

### 🚀 高性能・高信頼性
- **DuckDB** による高速データ処理（100万件以上の在庫データ対応）
- **接続プール** による効率的なリソース管理
- **非同期処理** による応答性の確保
- **トランザクション** による データ整合性保証

### 🔐 エンタープライズレベルのセキュリティ
- **JWT認証** によるセキュアなAPI アクセス
- **ロールベース** アクセス制御（管理者/マネージャー/ユーザー）
- **SQLインジェクション** 完全対策
- **セキュリティ監査ログ** による不正アクセス検知
- **アカウントロック** による ブルートフォース攻撃対策

### 🌐 RESTful Web API
- **OpenAPI 3.0** 準拠の設計
- **JSON** ベースの統一インターフェース
- **CORS** 対応によるクロスオリジンアクセス
- **レート制限** による負荷制御
- **多言語SDK** サポート（Julia, Python, JavaScript）

### 📊 Excel連携
- **完全な読み書き** 対応（.xlsx形式）
- **データ検証** による品質確保
- **一括インポート/エクスポート** 機能
- **テンプレート** 提供

### 🌍 日本語完全対応
- **UTF-8** による完全な日本語サポート
- **マルチバイト文字** の適切な処理
- **日本のビジネス慣行** に対応した設計

## 🏗️ システム アーキテクチャ

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

### コンポーネント構成

- **フロントエンド**: RESTful API クライアント（Web/Mobile/Desktop）
- **バックエンド**: Julia + Genie.jl Web フレームワーク
- **データベース**: DuckDB（高性能分析データベース）
- **認証**: JWT + BCrypt パスワードハッシュ
- **ログ**: 構造化JSON ログ + セキュリティ監査

## 🚀 クイックスタート

### 前提条件

- **Julia 1.9+** 
- **OS**: macOS, Linux, Windows
- **メモリ**: 4GB以上推奨
- **ディスク**: 1GB以上の空き容量

### インストール

```bash
# リポジトリをクローン
git clone https://github.com/your-org/julia_stock.git
cd julia_stock

# 依存関係をインストール
julia --project=. -e "using Pkg; Pkg.instantiate()"

# 必要なディレクトリを作成
mkdir -p data logs backups
```

### 起動

```julia
# Juliaを起動
julia --project=.

# システムを開始
julia> include("src/InventorySystem.jl")
julia> using .InventorySystem
julia> start_server(8000)
```

すると、以下のようなメッセージが表示されます：

```
=== Julia在庫管理システム v1.0.0 ===
システム初期化中...
認証システムを初期化中...
データベース接続プールを初期化中...
メインデータベースを初期化中...
管理者アカウントを確認中...
Webサーバーを起動中... (ポート: 8000)

✓ 在庫管理システムが正常に起動しました

🌐 API エンドポイント:
   - ベースURL: http://localhost:8000/api/
   - ヘルスチェック: http://localhost:8000/api/health
   - 在庫一覧: http://localhost:8000/api/stocks

🔐 認証:
   - ログイン: POST /api/auth/login
   - デフォルト管理者: admin / AdminPass123!

📖 ドキュメント: docs/API_SPECIFICATION.md
📋 運用マニュアル: docs/OPERATIONS_MANUAL.md
```

### 初回ログイン

```bash
# 管理者でログイン
curl -X POST http://localhost:8000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username": "admin", "password": "AdminPass123!"}'
```

## 📊 使用例

### 在庫データの追加

```julia
# 新しい在庫アイテムを作成
stock = Stock(
    1,                           # ID
    "ノートパソコン",              # 商品名
    "PC001",                     # 商品コード
    50,                          # 数量
    "台",                        # 単位
    80000.0,                     # 価格
    "電子機器",                   # カテゴリ
    "A-1-1",                     # 保管場所
    now(),                       # 作成日時
    now()                        # 更新日時
)

# データベースに保存
conn = get_connection_from_pool()
try
    secure_insert_stock(conn, stock)
finally
    return_connection_to_pool(conn)
end
```

### API経由での操作

```bash
# 在庫一覧取得
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:8000/api/stocks

# 在庫追加
curl -X POST \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "新商品",
    "code": "NEW001",
    "quantity": 100,
    "unit": "個",
    "price": 1500.0,
    "category": "新カテゴリ",
    "location": "B-2-1"
  }' \
  http://localhost:8000/api/stocks
```

### Excel連携

```julia
# 在庫データをExcelにエクスポート
stocks = secure_get_all_stocks(conn)
export_stocks_to_excel(stocks, "inventory_export.xlsx")

# Excelファイルからインポート
imported_stocks = import_stocks_from_excel("inventory_data.xlsx")
for stock in imported_stocks
    secure_insert_stock(conn, stock)
end
```

## 🔒 セキュリティ

### 認証・認可

- **JWT トークン** による ステートレス認証
- **BCrypt** による パスワードハッシュ化
- **ロールベース** アクセス制御
- **アカウントロック** 機能

### データ保護

- **パラメータ化クエリ** によるSQLインジェクション対策
- **入力値検証** による不正データ防止
- **セキュリティログ** による監査証跡
- **接続プール** による リソース保護

### 運用セキュリティ

```julia
# セキュリティ監査の実行
julia> security_audit()

# システム情報の確認
julia> system_info()

# ログ分析
julia> analyze_logs("logs/security.log", 24)  # 過去24時間
```

## 📈 パフォーマンス

### ベンチマーク結果

| 操作 | レコード数 | 処理時間 | メモリ使用量 |
|------|------------|----------|--------------|
| 在庫追加 | 10,000件 | 2.3秒 | 45MB |
| 検索 | 100万件から | 0.8秒 | 120MB |
| Excel エクスポート | 50,000件 | 4.1秒 | 200MB |
| 並行ユーザー | 50ユーザー | 平均200ms | 380MB |

### 最適化設定

```julia
# 高負荷環境用設定
init_connection_pool(
    max_connections = 50,
    min_connections = 10,
    connection_timeout = 60
)

# メモリ最適化
ENV["JULIA_GC_ALLOC_SYNCED"] = "1"
```

## 🧪 テスト

### テストスイートの実行

```bash
# 全テストを実行
julia --project=. test/runtests.jl

# 特定のテストのみ実行
julia --project=. test/test_stock_model.jl
julia --project=. test/test_duckdb_connection.jl
julia --project=. test/test_security.jl
```

### テスト カバレッジ

- **ユニットテスト**: 在庫モデル、データベース、認証
- **統合テスト**: エンドツーエンドワークフロー
- **セキュリティテスト**: SQLインジェクション、認証攻撃
- **負荷テスト**: 大量データ、並行処理
- **パフォーマンステスト**: レスポンス時間、スループット

### 継続的インテグレーション

GitHub Actions により自動実行：
- ✅ ユニットテスト
- ✅ セキュリティスキャン  
- ✅ コード品質チェック
- ✅ 依存関係監査

## 📚 ドキュメント

### API リファレンス
- **[API仕様書](docs/API_SPECIFICATION.md)** - REST API の完全仕様
- **[認証ガイド](docs/auth-guide.md)** - JWT認証の使用方法
- **[エラーコード](docs/error-codes.md)** - エラー対応ガイド

### 運用ガイド
- **[運用マニュアル](docs/OPERATIONS_MANUAL.md)** - システム運用の包括的ガイド
- **[バックアップ手順](docs/backup-procedures.md)** - データ保護戦略
- **[トラブルシューティング](docs/troubleshooting.md)** - 問題解決ガイド

### 開発者向け
- **[開発ガイド](docs/development-guide.md)** - コントリビューション方法
- **[アーキテクチャ](docs/architecture.md)** - システム設計詳細
- **[デプロイガイド](docs/deployment.md)** - 本番環境構築

## 🤝 コントリビューション

プロジェクトへの貢献を歓迎します！

### 開発環境のセットアップ

```bash
# 開発用依存関係をインストール
julia --project=. -e "using Pkg; Pkg.add([\"Revise\", \"JuliaFormatter\"])"

# プリコミットフックを設定
git config core.hooksPath .githooks
```

### コントリビューション プロセス

1. **Issue** を作成して変更内容を議論
2. **Fork** してフィーチャーブランチを作成
3. **テスト** を追加・実行
4. **コードフォーマット** を適用
5. **Pull Request** を作成

詳細は [CONTRIBUTING.md](CONTRIBUTING.md) をご覧ください。

## 📄 ライセンス

このプロジェクトは [MIT License](LICENSE) の下で公開されています。

## 🙋‍♂️ サポート

### 問題報告・機能要求
- **GitHub Issues**: バグ報告や機能要求
- **Discussions**: 質問や議論

### 商用サポート
企業向けサポート、カスタマイズ、トレーニングについては、お問い合わせください。

### コミュニティ
- **GitHub Discussions**: コミュニティ支援
- **Wiki**: 追加ドキュメントとTips

## 🗺️ ロードマップ

### v1.1.0 (予定)
- [ ] リアルタイム在庫通知
- [ ] 高度な在庫予測
- [ ] モバイルアプリ対応

### v1.2.0 (予定)  
- [ ] マルチテナント対応
- [ ] 高度なレポート機能
- [ ] 外部システム連携API

### v2.0.0 (予定)
- [ ] 機械学習による需要予測
- [ ] ブロックチェーン連携
- [ ] IoTデバイス統合

## 🏆 謝辞

このプロジェクトは以下のオープンソースプロジェクトに支えられています：

- **[Julia](https://julialang.org/)** - 高性能プログラミング言語
- **[DuckDB](https://duckdb.org/)** - 高速分析データベース  
- **[Genie.jl](https://genieframework.com/)** - Julia Web フレームワーク
- **[XLSX.jl](https://github.com/felipenoris/XLSX.jl)** - Excel ファイル処理

---

<div align="center">

**Julia在庫管理システム** で、あなたのビジネスを次のレベルへ 🚀

[📖 ドキュメント](docs/) | [🐛 Issues](https://github.com/your-org/julia_stock/issues) | [💬 Discussions](https://github.com/your-org/julia_stock/discussions) | [🌟 Star us on GitHub](https://github.com/your-org/julia_stock)

</div>
