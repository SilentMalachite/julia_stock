# Julia在庫管理システム API仕様書

## 概要

Julia在庫管理システムのRESTful API仕様書です。このAPIは認証が必要で、JWT トークンベースの認証を使用します。

**バージョン**: 1.0.0  
**ベースURL**: `http://localhost:8000/api`  
**認証方式**: JWT Bearer Token  
**Content-Type**: `application/json`

## 認証

### JWT トークンの取得

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
| **admin** | 全ての操作（作成、読み取り、更新、削除、ユーザー管理） |
| **manager** | 在庫の作成、読み取り、更新、削除、データエクスポート |
| **user** | 在庫の読み取り、データエクスポートのみ |

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

### 在庫管理

#### 在庫一覧取得

```http
GET /api/stocks
```

**クエリパラメータ:**
- `category` (optional): カテゴリでフィルタリング
- `limit` (optional): 取得件数制限（デフォルト: 1000）
- `offset` (optional): オフセット（デフォルト: 0）

**レスポンス例:**
```json
{
  "stocks": [
    {
      "id": 1,
      "name": "ノートパソコン",
      "code": "PC001",
      "quantity": 50,
      "unit": "台",
      "price": 80000.0,
      "category": "電子機器",
      "location": "A-1-1",
      "created_at": "2025-07-15T09:00:00Z",
      "updated_at": "2025-07-15T09:00:00Z"
    }
  ]
}
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
  "stock": {
    "id": 1,
    "name": "ノートパソコン",
    "code": "PC001",
    "quantity": 50,
    "unit": "台",
    "price": 80000.0,
    "category": "電子機器",
    "location": "A-1-1",
    "created_at": "2025-07-15T09:00:00Z",
    "updated_at": "2025-07-15T09:00:00Z"
  }
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
  "name": "新商品",
  "code": "NEW001",
  "quantity": 100,
  "unit": "個",
  "price": 1500.0,
  "category": "新カテゴリ",
  "location": "B-2-1"
}
```

**バリデーション:**
- `name`: 必須、1-255文字
- `code`: 必須、1-50文字、ユニーク
- `quantity`: 必須、0以上の整数
- `unit`: 必須、1-20文字
- `price`: 必須、0以上の数値
- `category`: 必須、1-100文字
- `location`: 必須、1-100文字

**レスポンス例:**
```json
{
  "stock": {
    "id": 123,
    "name": "新商品",
    "code": "NEW001",
    "quantity": 100,
    "unit": "個",
    "price": 1500.0,
    "category": "新カテゴリ",
    "location": "B-2-1",
    "created_at": "2025-07-15T10:30:00Z",
    "updated_at": "2025-07-15T10:30:00Z"
  }
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
  "stock": {
    "id": 1,
    "name": "ノートパソコン",
    "code": "PC001",
    "quantity": 150,
    "unit": "台",
    "price": 1800.0,
    "category": "電子機器",
    "location": "B-2-2",
    "created_at": "2025-07-15T09:00:00Z",
    "updated_at": "2025-07-15T10:45:00Z"
  }
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

**レスポンス:** 204 No Content

**エラー:**
- `404`: 在庫が見つからない

**必要な権限:** manager, admin

---

### 検索・フィルタリング

#### 在庫切れ商品取得

```http
GET /api/stocks/out-of-stock
```

**レスポンス例:**
```json
{
  "stocks": [
    {
      "id": 3,
      "name": "コピー用紙",
      "code": "CP001",
      "quantity": 0,
      "unit": "パック",
      "price": 300.0,
      "category": "オフィス用品",
      "location": "B-1-3",
      "created_at": "2025-07-15T09:00:00Z",
      "updated_at": "2025-07-15T09:00:00Z"
    }
  ]
}
```

**必要な権限:** user, manager, admin

---

#### 低在庫商品取得

```http
GET /api/stocks/low-stock?threshold=50
```

**クエリパラメータ:**
- `threshold`: 低在庫の閾値（デフォルト: 10）

**レスポンス例:**
```json
{
  "stocks": [
    {
      "id": 10,
      "name": "スマートフォン",
      "code": "SP001",
      "quantity": 5,
      "unit": "台",
      "price": 60000.0,
      "category": "電子機器",
      "location": "A-2-1",
      "created_at": "2025-07-15T09:00:00Z",
      "updated_at": "2025-07-15T09:00:00Z"
    }
  ]
}
```

**必要な権限:** user, manager, admin

---

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

### 統計・分析

#### 在庫統計取得

```http
GET /api/stats/inventory
```

**レスポンス例:**
```json
{
  "total_items": 500,
  "total_value": 12500000.0,
  "categories": {
    "電子機器": {
      "item_count": 150,
      "total_quantity": 800,
      "total_value": 8500000.0
    },
    "オフィス用品": {
      "item_count": 200,
      "total_quantity": 2500,
      "total_value": 250000.0
    }
  },
  "out_of_stock_count": 5,
  "low_stock_count": 15
}
```

**必要な権限:** manager, admin

---

## 認証・ユーザー管理

### ユーザー登録

```http
POST /auth/register
```

**リクエストボディ:**
```json
{
  "username": "newuser",
  "password": "SecurePass123!",
  "email": "newuser@example.com",
  "role": "user"
}
```

**パスワード要件:**
- 8文字以上
- 大文字・小文字・数字・特殊文字を含む

**レスポンス例:**
```json
{
  "message": "ユーザーが正常に作成されました",
  "username": "newuser",
  "role": "user"
}
```

**必要な権限:** admin

---

### パスワードリセット

```http
POST /auth/password-reset
```

**リクエストボディ:**
```json
{
  "username": "username"
}
```

**レスポンス例:**
```json
{
  "message": "パスワードリセットトークンが生成されました",
  "reset_token": "abc123def456"
}
```

---

### パスワードリセット実行

```http
POST /auth/password-reset/confirm
```

**リクエストボディ:**
```json
{
  "reset_token": "abc123def456",
  "new_password": "NewSecurePass123!"
}
```

**レスポンス例:**
```json
{
  "message": "パスワードが正常に更新されました"
}
```

---

## レート制限

- **一般API**: 100リクエスト/分
- **認証API**: 10リクエスト/分
- **ファイルアップロード**: 5リクエスト/分

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

# 在庫一覧取得
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

# 在庫一覧取得
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

// 在庫一覧取得
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

