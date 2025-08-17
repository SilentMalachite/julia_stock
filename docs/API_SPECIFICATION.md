# Julia在庫管理システム API仕様書

## 概要

Julia在庫管理システムのRESTful API仕様書です。このAPIは認証が必要で、JWT トークンベースの認証を使用します。

**バージョン**: 1.0.0  
**ベースURL**: `http://localhost:8000/api`  
**認証方式**: JWT Bearer Token  
**Content-Type**: `application/json`

## 認証

### JWT トークンの取得（ログイン）

すべてのAPI エンドポイントには認証が必要です。まず認証エンドポイントでJWT トークンを取得してください。

```http
POST /auth/login
Content-Type: application/json

{
  "username": "your_username",
  "password": "your_password"
}
```

**レスポンス:**
```json
{
  "username": "your_username",
  "role": "admin",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_at": "2025-07-16T12:00:00Z"
}
```

### 認証ヘッダー

取得したトークンをリクエストヘッダーに含めてください：

```http
Authorization: Bearer your_jwt_token_here
```

## 権限システム

| ロール | 権限 |
|--------|------|
| **admin** | 全ての操作（作成、読み取り、更新、削除、ユーザー管理、インポート/エクスポート、分析閲覧） |
| **manager** | 在庫の作成、読み取り、更新、削除、インポート/エクスポート、分析閲覧 |
| **user** | 在庫の読み取り、エクスポートのみ |

## エラーレスポンス形式

```json
{
  "error": true,
  "status": 400,
  "message": "エラーメッセージ",
  "timestamp": "2025-07-15T10:30:00Z",
  "error_id": "ERR_20250715103000_1234"
}
```

## API エンドポイント

### 在庫管理（v1）

#### 在庫一覧取得

```http
GET /api/stocks
```

（v1はシンプルな一覧です。カテゴリ等のフィルタは将来対応予定。）

**レスポンス例:**
```json
[
  {
    "id": 1,
    "product_code": "PC001",
    "product_name": "ノートパソコン",
    "quantity": 50,
    "unit": "台",
    "price": 80000.0,
    "category": "電子機器",
    "location": "A-1-1",
    "created_at": "2025-07-15T09:00:00Z",
    "updated_at": "2025-07-15T09:00:00Z"
  }
]
```

**必要な権限:** user, manager, admin

---

#### 在庫詳細取得

```http
GET /api/stocks/{id}
```

**パスパラメータ:**
- `id`: 在庫ID

**レスポンス例:**
```json
{
  "id": 1,
  "product_code": "PC001",
  "product_name": "ノートパソコン",
  "quantity": 50,
  "unit": "台",
  "price": 80000.0,
  "category": "電子機器",
  "location": "A-1-1",
  "created_at": "2025-07-15T09:00:00Z",
  "updated_at": "2025-07-15T09:00:00Z"
}
```

**エラー:**
- `404`: 在庫が見つからない

**必要な権限:** user, manager, admin

---

#### 在庫作成

```http
POST /api/stocks
```

**リクエストボディ:**
```json
{
  "product_name": "新商品",
  "product_code": "NEW001",
  "quantity": 100,
  "unit": "個",
  "price": 1500.0,
  "category": "新カテゴリ",
  "location": "B-2-1"
}
```

**バリデーション:**
- `product_name`: 必須、1-255文字
- `product_code`: 必須、1-50文字、ユニーク
- `quantity`: 必須、0以上の整数
- `unit`: 必須、1-20文字
- `price`: 必須、0以上の数値
- `category`: 必須、1-100文字
- `location`: 必須、1-100文字

**レスポンス例:**
```json
{
  "id": 123,
  "product_code": "NEW001",
  "product_name": "新商品",
  "quantity": 100,
  "unit": "個",
  "price": 1500.0,
  "category": "新カテゴリ",
  "location": "B-2-1",
  "created_at": "2025-07-15T10:30:00Z",
  "updated_at": "2025-07-15T10:30:00Z",
  "message": "在庫が正常に作成されました"
}
```

**エラー:**
- `400`: バリデーションエラー
- `409`: 商品コードの重複

**必要な権限:** manager, admin

---

#### 在庫更新

```http
PUT /api/stocks/{id}
```

**パスパラメータ:**
- `id`: 在庫ID

**リクエストボディ:**
```json
{
  "quantity": 150,
  "price": 1800.0,
  "location": "B-2-2"
}
```

**注意:** 更新したいフィールドのみ送信してください。

**レスポンス例:**
```json
{
  "id": 1,
  "product_code": "PC001",
  "product_name": "ノートパソコン",
  "quantity": 150,
  "unit": "台",
  "price": 1800.0,
  "category": "電子機器",
  "location": "B-2-2",
  "updated_at": "2025-07-15T10:45:00Z",
  "message": "在庫が正常に更新されました"
}
```

**エラー:**
- `404`: 在庫が見つからない
- `400`: バリデーションエラー

**必要な権限:** manager, admin

---

#### 在庫削除

```http
DELETE /api/stocks/{id}
```

**パスパラメータ:**
- `id`: 在庫ID

**レスポンス例:**
```json
{ "message": "在庫が正常に削除されました" }
```

**エラー:**
- `404`: 在庫が見つからない

**必要な権限:** manager, admin

---

### モダンAPI（v2）

#### 在庫一覧（ページネーション + 検索/ソート）

```http
GET /api/v2/stocks?page=1&limit=20&search=&category=&sortBy=updated_at&sortOrder=desc
```

**レスポンス例:**
```json
{
  "stocks": [ { "id": 1, "product_code": "PC001", "product_name": "ノートパソコン", ... } ],
  "currentPage": 1,
  "totalPages": 5,
  "totalItems": 100,
  "statistics": {
    "totalItems": 100,
    "totalValue": 1234567.89,
    "outOfStockItems": 2,
    "lowStockItems": 10,
    "categoryBreakdown": [ {"category":"電子機器","count":50,"value":800000.0} ]
  }
}
```

#### 在庫作成（バリデーション強化）

```http
POST /api/v2/stocks
```

リクエストボディは v1 と同様（`product_code`, `product_name`, `quantity` など）。

#### 在庫更新 / 削除

```http
PUT    /api/v2/stocks/{id}
DELETE /api/v2/stocks/{id}
```

#### 一括更新

```http
POST /api/v2/stocks/bulk-update
```

リクエスト例:
```json
{ "ids": [1,2,3], "updates": { "category": "新カテゴリ" } }
```

#### 詳細統計

```http
GET /api/v2/stocks/statistics
```

### Excel連携

#### Excel エクスポート

```http
GET /api/excel/export
```

**レスポンス:**
- Content-Type: `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet`
- バイナリデータ（Excelファイル）

**必要な権限:** user, manager, admin

---

#### Excel インポート

```http
POST /api/excel/import
Content-Type: multipart/form-data
```

**リクエストボディ:**
- `file`: Excelファイル（.xlsx形式）

**レスポンス例:**
```json
{
  "imported_count": 150,
  "errors": [],
  "message": "150件のデータが正常にインポートされました"
}
```

**エラー:**
- `400`: ファイル形式エラー
- `422`: データバリデーションエラー

**必要な権限:** manager, admin

---

### ヘルスチェック

```http
GET /api/health
```

公開エンドポイント。`{"status":"ok","timestamp":"..."}` を返します。

## 認証・ユーザー管理

ユーザー作成・パスワードリセット等の関数は内部には存在しますが、現在公開APIはログイン（`POST /api/auth/login`）のみです。

## レート制限（実装）

- 認証ログイン: 10 リクエスト/分（IP単位）
- 在庫作成/削除（v1/v2）: 120 リクエスト/分（IP単位）
- 在庫更新（v1/v2）: 240 リクエスト/分（IP単位）
- GET 系は現状レート制限なし

レート制限に達した場合、HTTP 429 ステータスコードが返されます。

## ステータスコード

| コード | 説明 |
|--------|------|
| 200 | 成功 |
| 201 | 作成成功 |
| 204 | 削除成功 |
| 400 | リクエストエラー |
| 401 | 認証エラー |
| 403 | 権限不足 |
| 404 | リソースが見つからない |
| 409 | データ競合 |
| 422 | バリデーションエラー |
| 429 | レート制限超過 |
| 500 | サーバーエラー |

## SDKとコード例

### Julia

```julia
using HTTP, JSON3

# 認証
auth_response = HTTP.post(
    "http://localhost:8000/api/auth/login",
    headers=["Content-Type" => "application/json"],
    body=JSON3.write(Dict("username" => "admin", "password" => "password"))
)
auth_data = JSON3.read(auth_response.body)
token = auth_data.token

# 在庫一覧取得（v1）
headers = ["Authorization" => "Bearer $token"]
response = HTTP.get("http://localhost:8000/api/stocks", headers=headers)
stocks = JSON3.read(response.body)
```

### Python

```python
import requests
import json

# 認証
auth_response = requests.post(
    "http://localhost:8000/api/auth/login",
    json={"username": "admin", "password": "password"}
)
token = auth_response.json()["token"]

# 在庫一覧取得（v1）
headers = {"Authorization": f"Bearer {token}"}
response = requests.get("http://localhost:8000/api/stocks", headers=headers)
stocks = response.json()
```

### JavaScript

```javascript
// 認証
const authResponse = await fetch('http://localhost:8000/api/auth/login', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'admin', password: 'password' })
});
const { token } = await authResponse.json();

// 在庫一覧取得（v1）
const response = await fetch('http://localhost:8000/api/stocks', {
  headers: { 'Authorization': `Bearer ${token}` }
});
const stocks = await response.json();
```

## 変更履歴

### v1.0.0 (2025-07-15)
- 初版リリース
- 基本的なCRUD操作
- JWT認証システム
- Excel連携機能
- セキュリティ強化

---

## サポート

技術サポートが必要な場合は、以下までお問い合わせください：

- **GitHub Issues**: https://github.com/SilentMalachite/julia_stock/issues
