module AuthenticationSystem

using Dates
using Random
using DuckDB
using DataFrames
using SHA
using Base64
using JSON3

# ユーザー構造体
struct User
    id::Int64
    username::String
    email::String
    password_hash::String
    role::String
    created_at::DateTime
    updated_at::DateTime
    is_active::Bool
    failed_login_attempts::Int64
    locked_until::Union{DateTime, Nothing}
end

# セッション構造体
struct Session
    session_id::String
    user_id::Int64
    expires_at::DateTime
    created_at::DateTime
end

# 認証結果構造体
struct AuthResult
    username::String
    role::String
    token::String
    expires_at::DateTime
end

export User, Session, AuthResult,
       create_user, delete_user, authenticate_user, verify_password, hash_password,
       generate_jwt_token, verify_jwt_token, has_permission,
       create_session, get_user_by_session, invalidate_session,
       is_account_locked, unlock_account, generate_password_reset_token, 
       reset_password_with_token, init_auth_database, get_all_users, change_password

# データベース接続（グローバル）
const AUTH_DB = Ref{Union{DuckDB.DB, Nothing}}(nothing)

# JWT秘密鍵は環境変数から取得
function get_jwt_secret()::String
    secret = get(ENV, "JWT_SECRET", "")
    if isempty(secret) || length(secret) < 16
        error("JWT_SECRET が未設定、または短すぎます（16文字以上を推奨）")
    end
    return secret
end

# 権限定義
const PERMISSIONS = Dict(
    "admin" => Set([
        "create_stock", "update_stock", "delete_stock", "view_all_stocks",
        "manage_users", "view_analytics", "export_data", "import_data"
    ]),
    "manager" => Set([
        "create_stock", "update_stock", "delete_stock", "view_all_stocks",
        "view_analytics", "export_data", "import_data"
    ]),
    "user" => Set([
        "view_all_stocks", "export_data"
    ])
)

function init_auth_database(db_path::String = "data/auth.db")
    """
    認証データベースを初期化
    """
    try
        # ディレクトリが無ければ作成
        try
            mkpath(dirname(db_path))
        catch
        end
        AUTH_DB[] = DuckDB.DB(db_path)
        create_auth_tables()
        println("認証データベースが初期化されました")
    catch e
        error("認証データベースの初期化に失敗しました: $e")
    end
end

function create_auth_tables()
    """
    認証関連のテーブルを作成
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    # ユーザーテーブル
    user_table_sql = """
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        username VARCHAR(50) UNIQUE NOT NULL,
        email VARCHAR(255) UNIQUE NOT NULL,
        password_hash VARCHAR(255) NOT NULL,
        role VARCHAR(20) NOT NULL CHECK (role IN ('admin', 'manager', 'user')),
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL,
        is_active BOOLEAN DEFAULT true,
        failed_login_attempts INTEGER DEFAULT 0,
        locked_until TIMESTAMP NULL
    )
    """
    
    # セッションテーブル
    session_table_sql = """
    CREATE TABLE IF NOT EXISTS sessions (
        session_id VARCHAR(128) PRIMARY KEY,
        user_id INTEGER NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        created_at TIMESTAMP NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
    )
    """
    
    # パスワードリセットトークンテーブル
    reset_token_sql = """
    CREATE TABLE IF NOT EXISTS password_reset_tokens (
        token VARCHAR(128) PRIMARY KEY,
        user_id INTEGER NOT NULL,
        expires_at TIMESTAMP NOT NULL,
        used BOOLEAN DEFAULT false,
        created_at TIMESTAMP NOT NULL,
        FOREIGN KEY (user_id) REFERENCES users(id)
    )
    """
    
    DuckDB.execute(AUTH_DB[], user_table_sql)
    DuckDB.execute(AUTH_DB[], session_table_sql)
    DuckDB.execute(AUTH_DB[], reset_token_sql)
end

function password_hash_iterations()::Int
    val = get(ENV, "PASSWORD_HASH_ITERATIONS", "10000")
    try
        iters = parse(Int, val)
        return max(iters, 1000) # 下限
    catch
        return 10000
    end
end

function stretch_sha256(password::String, salt_hex::String, iterations::Int)::Vector{UInt8}
    # シンプルなストレッチング（擬似PBKDF）
    data = Vector{UInt8}(password * salt_hex)
    digest = sha256(data)
    for _ in 2:iterations
        digest = sha256(vcat(digest, data))
    end
    return digest
end

function hash_password(password::String)::String
    """
    パスワードをハッシュ化（ソルト付き）
    """
    if length(password) < 8
        throw(ArgumentError("パスワードは8文字以上である必要があります"))
    end
    
    # パスワード強度チェック
    if !occursin(r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).*$", password)
        throw(ArgumentError("パスワードは大文字・小文字・数字・特殊文字を含む必要があります"))
    end
    
    # ランダムソルト + ストレッチング
    salt = bytes2hex(rand(UInt8, 16))
    iters = password_hash_iterations()
    digest = stretch_sha256(password, salt, iters)
    return join(["s2", string(iters), salt, bytes2hex(digest)], ":")
end

function verify_password(password::String, hash::String)::Bool
    """
    パスワードとハッシュを検証
    """
    try
        parts = split(hash, ":")
        if length(parts) == 4 && parts[1] == "s2"
            # 新フォーマット: s2:iter:salt:hex
            iters = parse(Int, parts[2])
            salt = parts[3]
            stored_hex = parts[4]
            calc = stretch_sha256(password, salt, iters)
            return secure_compare(hex_to_bytes(stored_hex), calc)
        elseif length(parts) == 2
            # 旧フォーマット: salt:hex（後方互換）
            salt = parts[1]
            stored = parts[2]
            hash_input = password * salt
            calc_hex = bytes2hex(sha256(hash_input))
            return constant_time_str_eq(calc_hex, stored)
        else
            return false
        end
    catch
        return false
    end
end

function validate_email(email::String)::Bool
    """
    メールアドレスの形式を検証
    """
    email_regex = r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$"
    return occursin(email_regex, email)
end

function create_user(username::String, password::String, email::String, role::String = "user")::User
    """
    新しいユーザーを作成
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    # 入力検証
    if length(username) < 3 || length(username) > 50
        throw(ArgumentError("ユーザー名は3-50文字である必要があります"))
    end
    
    if !occursin(r"^[a-zA-Z0-9_]+$", username)
        throw(ArgumentError("ユーザー名は英数字とアンダースコアのみ使用できます"))
    end
    
    if !validate_email(email)
        throw(ArgumentError("有効なメールアドレスを入力してください"))
    end
    
    if !(role in ["admin", "manager", "user"])
        throw(ArgumentError("無効な役割です"))
    end
    
    # ユーザー名とメールの重複チェック
    existing_user_sql = "SELECT COUNT(*) as count FROM users WHERE username = ? OR email = ?"
    result = DuckDB.execute(AUTH_DB[], existing_user_sql, [username, email])
    df = DataFrame(result)
    
    if df[1, :count] > 0
        throw(ArgumentError("ユーザー名またはメールアドレスが既に存在します"))
    end
    
    # パスワードハッシュ化
    password_hash = hash_password(password)
    
    # ユーザーID生成
    user_id = Int64(round(datetime2unix(now()) * 1000))
    current_time = now()
    
    # ユーザー挿入
    insert_sql = """
    INSERT INTO users (id, username, email, password_hash, role, created_at, updated_at, is_active, failed_login_attempts, locked_until)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    DuckDB.execute(AUTH_DB[], insert_sql, [
        user_id, username, email, password_hash, role, 
        current_time, current_time, true, 0, nothing
    ])
    
    return User(user_id, username, email, password_hash, role, current_time, current_time, true, 0, nothing)
end

function delete_user(username::String)
    """
    ユーザーを削除
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    delete_sql = "DELETE FROM users WHERE username = ?"
    DuckDB.execute(AUTH_DB[], delete_sql, [username])
end

function get_user_by_username(username::String)::Union{User, Nothing}
    """
    ユーザー名でユーザーを取得
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    sql = "SELECT * FROM users WHERE username = ? AND is_active = true"
    result = DuckDB.execute(AUTH_DB[], sql, [username])
    df = DataFrame(result)
    
    if nrow(df) == 0
        return nothing
    end
    
    row = df[1, :]
    locked_until = row.locked_until === missing ? nothing : row.locked_until
    
    return User(
        row.id, row.username, row.email, row.password_hash, row.role,
        row.created_at, row.updated_at, row.is_active, row.failed_login_attempts, locked_until
    )
end

function update_failed_login_attempts(username::String, attempts::Int64)
    """
    ログイン失敗回数を更新
    """
    if AUTH_DB[] === nothing
        return
    end
    
    locked_until = attempts >= 5 ? now() + Hour(1) : nothing
    
    sql = """
    UPDATE users 
    SET failed_login_attempts = ?, locked_until = ?, updated_at = ?
    WHERE username = ?
    """
    
    DuckDB.execute(AUTH_DB[], sql, [attempts, locked_until, now(), username])
end

function reset_failed_login_attempts(username::String)
    """
    ログイン失敗回数をリセット
    """
    if AUTH_DB[] === nothing
        return
    end
    
    sql = """
    UPDATE users 
    SET failed_login_attempts = 0, locked_until = NULL, updated_at = ?
    WHERE username = ?
    """
    
    DuckDB.execute(AUTH_DB[], sql, [now(), username])
end

function is_account_locked(username::String)::Bool
    """
    アカウントがロックされているかチェック
    """
    user = get_user_by_username(username)
    if user === nothing
        return false
    end
    
    if user.locked_until !== nothing && user.locked_until > now()
        return true
    end
    
    return false
end

function unlock_account(username::String)
    """
    アカウントロックを解除
    """
    reset_failed_login_attempts(username)
end

function authenticate_user(username::String, password::String)::Union{AuthResult, Nothing}
    """
    ユーザー認証
    """
    if isempty(username) || isempty(password)
        return nothing
    end
    
    # アカウントロックチェック
    if is_account_locked(username)
        return nothing
    end
    
    user = get_user_by_username(username)
    if user === nothing
        return nothing
    end
    
    # パスワード検証
    if !verify_password(password, user.password_hash)
        # ログイン失敗回数を増加
        update_failed_login_attempts(username, user.failed_login_attempts + 1)
        return nothing
    end
    
    # ログイン成功 - 失敗回数をリセット
    reset_failed_login_attempts(username)
    
    # JWTトークン生成
    token = generate_jwt_token(user)
    expires_at = now() + Hour(24)  # 24時間有効
    
    return AuthResult(user.username, user.role, token, expires_at)
end

function b64url_encode(bytes::Vector{UInt8})::String
    s = base64encode(bytes)
    s = replace(s, "+" => "-", "/" => "_")
    replace(s, "=" => "")
end

function b64url_decode(s::String)::Vector{UInt8}
    t = replace(s, "-" => "+", "_" => "/")
    pad = (4 - (length(t) % 4)) % 4
    t *= repeat("=", pad)
    base64decode(t)
end

function constant_time_str_eq(a::String, b::String)::Bool
    if ncodeunits(a) != ncodeunits(b)
        return false
    end
    diff = 0
    @inbounds for i in 1:ncodeunits(a)
        diff |= Int(codeunit(a, i)) ⊻ Int(codeunit(b, i))
    end
    return diff == 0
end

function hex_to_bytes(hex::String)::Vector{UInt8}
    n = length(hex)
    if isodd(n)
        error("invalid hex length")
    end
    out = Vector{UInt8}(undef, n >>> 1)
    j = 1
    @inbounds for i in 1:2:n
        out[j] = parse(UInt8, hex[i:i+1], base=16)
        j += 1
    end
    return out
end

function secure_compare(a::Vector{UInt8}, b::Vector{UInt8})::Bool
    if length(a) != length(b)
        return false
    end
    diff = UInt8(0)
    @inbounds for i in eachindex(a, b)
        diff |= a[i] ⊻ b[i]
    end
    return diff == 0x00
end

function generate_jwt_token(user::User; expires_in::Int = 86400)::String
    """
    JWTトークンを生成（簡易版）
    """
    # ヘッダー
    header = Dict("alg" => "HS256", "typ" => "JWT")
    header_json = JSON3.write(header)
    header_b64 = b64url_encode(Vector{UInt8}(header_json))
    
    # ペイロード
    exp_time = now() + Second(expires_in)
    payload = Dict(
        "user_id" => user.id,
        "username" => user.username,
        "role" => user.role,
        "exp" => datetime2unix(exp_time),
        "iat" => datetime2unix(now())
    )
    payload_json = JSON3.write(payload)
    payload_b64 = b64url_encode(Vector{UInt8}(payload_json))
    
    # 署名
    message = header_b64 * "." * payload_b64
    signature = hmac_sha256(get_jwt_secret(), message)
    signature_b64 = b64url_encode(signature)
    
    return header_b64 * "." * payload_b64 * "." * signature_b64
end

function verify_jwt_token(token::String)::Union{User, Nothing}
    """
    JWTトークンを検証（簡易版）
    """
    try
        parts = split(token, ".")
        if length(parts) != 3
            return nothing
        end

        header_b64, payload_b64, signature_b64 = parts
        # 署名検証（Base64URL）
        message = header_b64 * "." * payload_b64
        expected_sig = hmac_sha256(get_jwt_secret(), message)
        given_sig = b64url_decode(signature_b64)
        if !secure_compare(expected_sig, given_sig)
            return nothing
        end

        # ペイロード解析
        payload_json = String(b64url_decode(payload_b64))
        payload = JSON3.read(payload_json)

        # 期限チェック
        if payload.exp < datetime2unix(now())
            return nothing
        end

        return get_user_by_username(payload.username)
    catch
        return nothing
    end
end

function has_permission(user::User, permission::String)::Bool
    """
    ユーザーが特定の権限を持っているかチェック
    """
    user_permissions = get(PERMISSIONS, user.role, Set{String}())
    return permission in user_permissions
end

function create_session(user::User; expires_in::Int = 86400)::Session
    """
    セッションを作成
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    session_id = bytes2hex(rand(UInt8, 32))
    expires_at = now() + Second(expires_in)
    current_time = now()
    
    sql = """
    INSERT INTO sessions (session_id, user_id, expires_at, created_at)
    VALUES (?, ?, ?, ?)
    """
    
    DuckDB.execute(AUTH_DB[], sql, [session_id, user.id, expires_at, current_time])
    
    return Session(session_id, user.id, expires_at, current_time)
end

function get_user_by_session(session_id::String)::Union{User, Nothing}
    """
    セッションIDからユーザーを取得
    """
    if AUTH_DB[] === nothing
        return nothing
    end
    
    sql = """
    SELECT u.* FROM users u
    JOIN sessions s ON u.id = s.user_id
    WHERE s.session_id = ? AND s.expires_at > ? AND u.is_active = true
    """
    
    result = DuckDB.execute(AUTH_DB[], sql, [session_id, now()])
    df = DataFrame(result)
    
    if nrow(df) == 0
        return nothing
    end
    
    row = df[1, :]
    locked_until = row.locked_until === missing ? nothing : row.locked_until
    
    return User(
        row.id, row.username, row.email, row.password_hash, row.role,
        row.created_at, row.updated_at, row.is_active, row.failed_login_attempts, locked_until
    )
end

function invalidate_session(session_id::String)
    """
    セッションを無効化
    """
    if AUTH_DB[] === nothing
        return
    end
    
    sql = "DELETE FROM sessions WHERE session_id = ?"
    DuckDB.execute(AUTH_DB[], sql, [session_id])
end

function generate_password_reset_token(username::String)::String
    """
    パスワードリセットトークンを生成
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    user = get_user_by_username(username)
    if user === nothing
        throw(ArgumentError("ユーザーが見つかりません"))
    end
    
    token = bytes2hex(rand(UInt8, 32))
    expires_at = now() + Hour(1)  # 1時間有効
    
    sql = """
    INSERT INTO password_reset_tokens (token, user_id, expires_at, created_at)
    VALUES (?, ?, ?, ?)
    """
    
    DuckDB.execute(AUTH_DB[], sql, [token, user.id, expires_at, now()])
    
    return token
end

function reset_password_with_token(token::String, new_password::String)
    """
    トークンを使ってパスワードをリセット
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    # トークン検証
    sql = """
    SELECT user_id FROM password_reset_tokens 
    WHERE token = ? AND expires_at > ? AND used = false
    """
    
    result = DuckDB.execute(AUTH_DB[], sql, [token, now()])
    df = DataFrame(result)
    
    if nrow(df) == 0
        throw(ArgumentError("無効または期限切れのトークンです"))
    end
    
    user_id = df[1, :user_id]
    
    # 新しいパスワードをハッシュ化
    new_password_hash = hash_password(new_password)
    
    # パスワード更新
    update_sql = """
    UPDATE users 
    SET password_hash = ?, updated_at = ?
    WHERE id = ?
    """
    
    DuckDB.execute(AUTH_DB[], update_sql, [new_password_hash, now(), user_id])
    
    # トークンを使用済みにマーク
    mark_used_sql = "UPDATE password_reset_tokens SET used = true WHERE token = ?"
    DuckDB.execute(AUTH_DB[], mark_used_sql, [token])
end

# HMAC-SHA256の簡易実装（本番環境では適切なライブラリを使用）
function hmac_sha256(key::String, message::String)::Vector{UInt8}
    """
    HMAC-SHA256の簡易実装
    """
    key_bytes = Vector{UInt8}(key)
    message_bytes = Vector{UInt8}(message)
    
    blocksize = 64
    
    if length(key_bytes) > blocksize
        key_bytes = sha256(key_bytes)
    end
    
    if length(key_bytes) < blocksize
        key_bytes = vcat(key_bytes, zeros(UInt8, blocksize - length(key_bytes)))
    end
    
    o_key_pad = key_bytes .⊻ 0x5c
    i_key_pad = key_bytes .⊻ 0x36
    
    return sha256(vcat(o_key_pad, sha256(vcat(i_key_pad, message_bytes))))
end

function get_all_users()::Vector{User}
    """
    全ユーザー一覧を取得
    
    Returns:
        Vector{User}: 全ユーザーのリスト
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    sql = """
    SELECT id, username, email, password_hash, role, created_at, updated_at, 
           is_active, failed_login_attempts, locked_until
    FROM users
    ORDER BY created_at DESC
    """
    
    result = DuckDB.execute(AUTH_DB[], sql)
    df = DataFrame(result)
    
    users = User[]
    for row in eachrow(df)
        push!(users, User(
            row.id,
            row.username,
            row.email,
            row.password_hash,
            row.role,
            row.created_at,
            row.updated_at,
            row.is_active,
            row.failed_login_attempts,
            row.locked_until
        ))
    end
    
    return users
end

function change_password(username::String, old_password::String, new_password::String)
    """
    ユーザーのパスワードを変更
    
    Args:
        username: ユーザー名
        old_password: 現在のパスワード
        new_password: 新しいパスワード
    """
    if AUTH_DB[] === nothing
        throw(ArgumentError("認証データベースが初期化されていません"))
    end
    
    # 現在のパスワード検証（認証APIは例外を投げないため明示検証）
    user = get_user_by_username(username)
    if user === nothing || !verify_password(old_password, user.password_hash)
        throw(ArgumentError("現在のパスワードが正しくありません"))
    end
    
    # 新しいパスワードをハッシュ化
    new_password_hash = hash_password(new_password)
    
    # パスワード更新
    sql = """
    UPDATE users 
    SET password_hash = ?, updated_at = ?
    WHERE username = ?
    """
    
    DuckDB.execute(AUTH_DB[], sql, [new_password_hash, now(), username])
end

end
