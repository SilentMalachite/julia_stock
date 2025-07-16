# コントリビューションガイド

Julia在庫管理システムへのコントリビューションを歓迎します！このガイドでは、プロジェクトに貢献する方法について説明します。

## 📋 目次

1. [行動規範](#行動規範)
2. [始め方](#始め方)
3. [開発環境のセットアップ](#開発環境のセットアップ)
4. [コントリビューションの種類](#コントリビューションの種類)
5. [開発ワークフロー](#開発ワークフロー)
6. [コーディング規約](#コーディング規約)
7. [テストガイドライン](#テストガイドライン)
8. [ドキュメント](#ドキュメント)
9. [リリースプロセス](#リリースプロセス)

## 📜 行動規範

このプロジェクトは包括的で歓迎的なコミュニティを目指しています。参加にあたって：

- **尊重**: 他の参加者を尊重し、建設的な議論を心がけてください
- **包括性**: 経験レベルや背景に関係なく、すべての貢献を歓迎します
- **協力**: 協力的な態度で、お互いから学び合いましょう
- **プロフェッショナリズム**: 技術的な議論に集中し、個人攻撃は避けてください

## 🚀 始め方

### 貢献できる分野

- 🐛 **バグ修正**: 既存の問題を解決
- ✨ **新機能**: 新しい機能や改善の実装
- 📖 **ドキュメント**: ドキュメントの改善や翻訳
- 🧪 **テスト**: テストケースの追加や改善
- 🔧 **ツール**: 開発ツールやCI/CDの改善
- 🎨 **UI/UX**: ユーザーインターフェースの改善
- 🌍 **国際化**: 多言語対応の改善

### 最初のコントリビューション

初めての方は、以下のラベルが付いたissueから始めることをお勧めします：

- `good first issue` - 初心者向けの問題
- `help wanted` - コミュニティからの支援が必要
- `documentation` - ドキュメント関連
- `beginner-friendly` - 経験の浅い開発者向け

## 🛠️ 開発環境のセットアップ

### 必要な環境

- **Julia 1.9+**: [公式サイト](https://julialang.org/downloads/)からダウンロード
- **Git**: バージョン管理
- **テキストエディタ**: VS Code、Vim、またはお好みのエディタ
- **Docker** (オプション): コンテナ化されたテスト環境

### セットアップ手順

```bash
# 1. リポジトリをフォーク・クローン
git clone https://github.com/SilentMalachite/julia_stock.git
cd julia_stock

# 2. 依存関係をインストール
julia --project=. -e "using Pkg; Pkg.instantiate()"

# 3. 開発用パッケージをインストール
julia --project=. -e "using Pkg; Pkg.add([\"Revise\", \"JuliaFormatter\", \"BenchmarkTools\"])"

# 4. 必要なディレクトリを作成
mkdir -p data logs backups

# 5. テストを実行して動作確認
julia --project=. test/runtests.jl
```

- **Julia 1.9+**
- **Git**
- **VS Code** (推奨エディタ) + Julia拡張機能
- **DuckDB** (自動インストール)

### セットアップ手順

```bash
# 1. リポジトリをフォーク・クローン
git clone https://github.com/SilentMalachite/julia_stock.git
cd julia_stock

# 2. アップストリームリモートを追加
git remote add upstream https://github.com/SilentMalachite/julia_stock.git

# 3. 依存関係をインストール
julia --project=. -e "using Pkg; Pkg.instantiate()"

# 4. 開発用パッケージを追加
julia --project=. -e "using Pkg; Pkg.add([\"Revise\", \"JuliaFormatter\", \"BenchmarkTools\"])"

# 5. プリコミットフックを設定
cp .githooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit

# 6. 開発環境テスト
julia --project=. test/runtests.jl
```

### 推奨VS Code設定

`.vscode/settings.json`:
```json
{
    "julia.environmentPath": ".",
    "julia.enableTelemetry": false,
    "files.insertFinalNewline": true,
    "files.trimTrailingWhitespace": true,
    "[julia]": {
        "editor.tabSize": 4,
        "editor.insertSpaces": true,
        "editor.rulers": [92]
    }
}
```

## 🤝 コントリビューションの種類

### 1. バグ報告

バグを発見した場合は、以下の情報を含めてissueを作成してください：

```markdown
## バグの説明
簡潔で明確な説明

## 再現手順
1. ...
2. ...
3. ...

## 期待される動作
何が起こるべきかの説明

## 実際の動作
実際に何が起こったかの説明

## 環境情報
- OS: [例: macOS 13.0]
- Julia version: [例: 1.9.2]
- プロジェクトバージョン: [例: v1.0.0]

## 追加情報
スクリーンショット、ログファイルなど
```

### 2. 機能要求

新機能を提案する場合：

```markdown
## 機能の説明
提案する機能の明確な説明

## 動機
なぜこの機能が必要か

## 詳細設計
可能であれば、実装の詳細

## 代替案
検討した他の解決策

## 追加情報
関連するissueやPRのリンク
```

### 3. プルリクエスト

PRを作成する前に：

1. **Issue作成**: 大きな変更の場合、まずissueで議論
2. **ブランチ作成**: `feature/description` または `fix/issue-number`
3. **テスト追加**: 新機能やバグ修正にはテストを追加
4. **ドキュメント更新**: 必要に応じてドキュメントを更新

## 🔄 開発ワークフロー

### ブランチ戦略

```bash
# 1. 最新のmainブランチを取得
git checkout main
git pull upstream main

# 2. 新しいブランチを作成
git checkout -b feature/awesome-feature

# 3. 変更を実装
# ...

# 4. テストを実行
julia --project=. test/runtests.jl

# 5. コミット
git add .
git commit -m "feat: add awesome feature

- 新機能Xを追加
- 関連テストを追加
- ドキュメントを更新

Fixes #123"

# 6. プッシュ
git push origin feature/awesome-feature

# 7. プルリクエストを作成
```

### コミットメッセージ規約

[Conventional Commits](https://www.conventionalcommits.org/)に従います：

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**タイプ**:
- `feat`: 新機能
- `fix`: バグ修正
- `docs`: ドキュメントのみの変更
- `style`: コードの意味に影響しない変更（空白、フォーマットなど）
- `refactor`: バグ修正や機能追加ではないコード変更
- `perf`: パフォーマンス改善
- `test`: テストの追加や修正
- `chore`: ビルドプロセスや補助ツールの変更

**例**:
```
feat(auth): add JWT token refresh functionality

- JWTトークンの自動更新機能を追加
- 有効期限間近での自動リフレッシュを実装
- 関連するテストケースを追加

Closes #45
```

## 📝 コーディング規約

### Julia コーディングスタイル

1. **命名規約**:
   ```julia
   # 関数名: snake_case
   function calculate_total_value()
   
   # 型名: PascalCase
   struct InventoryItem
   
   # 定数: UPPER_CASE
   const MAX_CONNECTIONS = 100
   
   # 変数: snake_case
   user_count = 10
   ```

2. **インデント**: 4スペース

3. **行長**: 92文字以内

4. **コメント**:
   ```julia
   """
   在庫アイテムの総価値を計算する
   
   Args:
       items: 在庫アイテムのリスト
       
   Returns:
       Float64: 総価値
   """
   function calculate_total_value(items::Vector{Stock})::Float64
       return sum(item.price * item.quantity for item in items)
   end
   ```

### フォーマッター

プロジェクトでは[JuliaFormatter.jl](https://github.com/domluna/JuliaFormatter.jl)を使用：

```bash
# フォーマットを適用
julia --project=. -e "using JuliaFormatter; format(\".\")"

# フォーマットチェック
julia --project=. -e "using JuliaFormatter; format(\".\", verbose=true) || exit(1)"
```

## 🧪 テストガイドライン

### テスト構造

```
test/
├── runtests.jl              # メインテストランナー
├── test_stock_model.jl      # モデルテスト
├── test_security.jl         # セキュリティテスト
├── test_authentication.jl   # 認証テスト
├── test_integration.jl      # 統合テスト
└── test_performance.jl      # パフォーマンステスト
```

### テスト作成指針

1. **単体テスト**: 各関数・メソッドのテスト
   ```julia
   @testset "Stock creation tests" begin
       @test Stock(1, "Test", "T001", 10, "個", 100.0, "Category", "Location", now(), now()) isa Stock
       @test_throws ArgumentError Stock(-1, "Test", "T001", 10, "個", 100.0, "Category", "Location", now(), now())
   end
   ```

2. **統合テスト**: システム全体のワークフロー
   ```julia
   @testset "End-to-end inventory workflow" begin
       # ユーザー認証
       user = authenticate_user("test_user", "password")
       @test user !== nothing
       
       # 在庫追加
       stock = create_stock(user, stock_data)
       @test stock.id > 0
       
       # 在庫検索
       found_stock = find_stock_by_id(stock.id)
       @test found_stock.name == stock_data.name
   end
   ```

3. **セキュリティテスト**: 攻撃に対する耐性
   ```julia
   @testset "SQL injection protection" begin
       malicious_input = "'; DROP TABLE stocks; --"
       @test_nowarn secure_get_stocks_by_category(conn, malicious_input)
       @test secure_table_exists(conn, "stocks") == true
   end
   ```

### テスト実行

```bash
# 全テスト実行
julia --project=. test/runtests.jl

# 特定テスト実行
julia --project=. -e "include(\"test/test_security.jl\")"

# カバレッジ測定
julia --project=. --code-coverage=user test/runtests.jl
```

## 📖 ドキュメント

### ドキュメント構造

```
docs/
├── API_SPECIFICATION.md     # API仕様書
├── OPERATIONS_MANUAL.md     # 運用マニュアル
├── architecture.md          # アーキテクチャ設計
├── deployment.md            # デプロイガイド
├── troubleshooting.md       # トラブルシューティング
└── examples/                # 使用例
```

### ドキュメント作成指針

1. **明確性**: 技術的でない読者にも理解できる説明
2. **具体性**: コード例や実際の使用ケースを含める
3. **最新性**: コード変更に合わせてドキュメントを更新
4. **国際化**: 英語と日本語の両方で提供

### 関数ドキュメント

```julia
"""
    secure_insert_stock(connection::DuckDB.DB, stock::Stock) -> Bool

在庫アイテムを安全にデータベースに挿入する

この関数は、SQLインジェクション攻撃を防ぐためにパラメータ化クエリを使用し、
入力値の検証を行った後にデータベースに在庫情報を挿入します。

# Arguments
- `connection::DuckDB.DB`: データベース接続
- `stock::Stock`: 挿入する在庫アイテム

# Returns
- `Bool`: 挿入が成功した場合はtrue、失敗した場合はfalse

# Throws
- `ArgumentError`: 無効な在庫データの場合
- `SQLError`: データベースエラーの場合

# Examples
```julia
conn = secure_db_connect()
stock = Stock(1, "商品名", "CODE001", 10, "個", 1000.0, "カテゴリ", "場所", now(), now())
success = secure_insert_stock(conn, stock)
if success
    println("在庫が正常に追加されました")
end
```

# Security
この関数は以下のセキュリティ対策を実装しています：
- パラメータ化クエリによるSQLインジェクション防止
- 入力値の検証とサニタイゼーション
- セキュリティイベントのログ記録

# See Also
- [`secure_update_stock`](@ref): 在庫の更新
- [`secure_delete_stock`](@ref): 在庫の削除
"""
function secure_insert_stock(connection::DuckDB.DB, stock::Stock)::Bool
    # 実装...
end
```

## 🚢 リリースプロセス

### バージョニング

[Semantic Versioning (SemVer)](https://semver.org/)に従います：

- `MAJOR.MINOR.PATCH`
- **MAJOR**: 破壊的変更
- **MINOR**: 後方互換性のある機能追加
- **PATCH**: 後方互換性のあるバグ修正

### リリース手順

1. **準備**:
   ```bash
   # 全テストの実行
   julia --project=. test/runtests.jl
   
   # セキュリティ監査
   julia --project=. scripts/security_audit.jl
   
   # ドキュメント更新確認
   ```

2. **リリースブランチ作成**:
   ```bash
   git checkout -b release/v1.1.0
   ```

3. **バージョン更新**:
   - `Project.toml`のバージョン番号更新
   - `CHANGELOG.md`の更新

4. **タグ作成**:
   ```bash
   git tag -a v1.1.0 -m "Release version 1.1.0"
   git push origin v1.1.0
   ```

## 🎯 品質保証

### 自動チェック

プルリクエストでは以下が自動実行されます：

- ✅ **ユニットテスト**: 全テストの実行
- ✅ **セキュリティスキャン**: 脆弱性チェック
- ✅ **コード品質**: 静的解析
- ✅ **フォーマット**: コードスタイルチェック
- ✅ **ドキュメント**: ドキュメント生成テスト

### 手動レビュー

コードレビューでは以下を確認：

1. **機能性**: 要求された機能が正しく実装されているか
2. **セキュリティ**: セキュリティ上の問題がないか
3. **パフォーマンス**: パフォーマンスへの悪影響がないか
4. **可読性**: コードが理解しやすいか
5. **テスト**: 適切なテストが追加されているか

## 🆘 ヘルプが必要な場合

### コミュニティサポート

- **GitHub Discussions**: 一般的な質問や議論
- **GitHub Issues**: 具体的な問題やバグ報告
- **Discord/Slack**: リアルタイムでの質問（もしあれば）


## 🏆 貢献者の認識

### 貢献者リスト

すべての貢献者は以下で認識されます：

- `CONTRIBUTORS.md`ファイルでの記載
- リリースノートでの感謝
- GitHub "Contributors" セクション

### 貢献の種類

- 💻 コード
- 📖 ドキュメント
- 🎨 デザイン
- 🤔 アイデア・企画
- 🧪 テスト
- 🐛 バグ報告
- 💬 質問応答
- 📢 普及活動

---

プロジェクトへの参加ありがとうございます！一緒に素晴らしいソフトウェアを作りましょう 🚀
