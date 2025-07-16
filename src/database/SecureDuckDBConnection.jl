module SecureDuckDBConnection

using DuckDB
using DataFrames
using Dates
using ..StockModel

export secure_db_connect, secure_db_close, secure_create_stock_table, secure_table_exists,
       secure_insert_stock, secure_get_all_stocks, secure_get_stock_by_id, 
       secure_update_stock, secure_delete_stock, secure_get_stocks_by_category, 
       secure_get_out_of_stock_items, secure_get_low_stock_items,
       secure_begin_transaction, secure_commit_transaction, secure_rollback_transaction,
       validate_input, sanitize_string

# 入力検証とサニタイゼーション
function validate_input(value::Any, field_name::String, max_length::Int = 255)
    """
    入力値を検証する
    
    Args:
        value: 検証する値
        field_name: フィールド名
        max_length: 最大文字数
    """
    if value === nothing || value === missing
        throw(ArgumentError("$field_name は必須です"))
    end
    
    str_value = string(value)
    
    # 長さ制限チェック
    if length(str_value) > max_length
        throw(ArgumentError("$field_name は $max_length 文字以内である必要があります"))
    end
    
    # NULLバイト検出
    if contains(str_value, '\0')
        throw(ArgumentError("$field_name にNULLバイトは使用できません"))
    end
    
    # 基本的なSQLインジェクション文字列の検出
    dangerous_patterns = [
        r"(?i)(union\s+select|drop\s+table|delete\s+from|insert\s+into|update\s+.+set)",
        r"(?i)(exec\s*\(|sp_|xp_|--|\;)",
        r"(?i)(script\s*>|javascript:|vbscript:)",
        r"(?i)(waitfor\s+delay|benchmark\s*\(|sleep\s*\()"
    ]
    
    for pattern in dangerous_patterns
        if occursin(pattern, str_value)
            throw(ArgumentError("$field_name に不正な文字列が含まれています"))
        end
    end
    
    return str_value
end

function sanitize_string(input::String)::String
    """
    文字列をサニタイズする
    
    Args:
        input: サニタイズする文字列
        
    Returns:
        String: サニタイズされた文字列
    """
    # HTMLエスケープ
    sanitized = replace(input, r"[<>&\"']" => s -> 
        s == "<" ? "&lt;" :
        s == ">" ? "&gt;" :
        s == "&" ? "&amp;" :
        s == "\"" ? "&quot;" :
        s == "'" ? "&#x27;" : s
    )
    
    # 制御文字の除去
    sanitized = replace(sanitized, r"[\x00-\x1f\x7f]" => "")
    
    return sanitized
end

function secure_db_connect(db_path::String = ":memory:")::DuckDB.DB
    """
    セキュアなDuckDBデータベース接続を確立する
    
    Args:
        db_path: データベースファイルのパス
    
    Returns:
        DuckDB.DB: データベース接続オブジェクト
    """
    # パス検証
    if db_path != ":memory:"
        # パストラバーサル攻撃の防止
        if occursin(r"\.\.", db_path) || occursin(r"[/\\]\.\.+[/\\]", db_path)
            throw(ArgumentError("不正なデータベースパスです"))
        end
        
        # 特殊なデバイスファイルの防止
        dangerous_paths = ["/dev/", "/proc/", "/sys/", "\\\\", "/etc/"]
        if any(contains(db_path, dangerous) for dangerous in dangerous_paths)
            throw(ArgumentError("システムパスへのアクセスは禁止されています"))
        end
    end
    
    try
        conn = DuckDB.DB(db_path)
        
        # セキュリティ設定を適用
        # Note: DuckDBの具体的なセキュリティオプションは実装に依存
        
        return conn
    catch e
        error("セキュアなデータベース接続に失敗しました: $e")
    end
end

function secure_db_close(conn::DuckDB.DB)
    """
    データベース接続を安全に閉じる
    """
    try
        DuckDB.close(conn)
    catch e
        @warn "データベース接続の終了中にエラーが発生しました: $e"
    end
end

function secure_create_stock_table(conn::DuckDB.DB)
    """
    セキュアな在庫テーブルを作成する
    """
    sql = """
    CREATE TABLE IF NOT EXISTS stocks (
        id INTEGER PRIMARY KEY,
        name VARCHAR(255) NOT NULL CHECK (length(name) > 0 AND length(name) <= 255),
        code VARCHAR(50) UNIQUE NOT NULL CHECK (length(code) > 0 AND length(code) <= 50),
        quantity INTEGER NOT NULL CHECK (quantity >= 0),
        unit VARCHAR(20) NOT NULL CHECK (length(unit) > 0 AND length(unit) <= 20),
        price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
        category VARCHAR(100) NOT NULL CHECK (length(category) > 0 AND length(category) <= 100),
        location VARCHAR(100) NOT NULL CHECK (length(location) > 0 AND length(location) <= 100),
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL
    )
    """
    
    try
        DuckDB.execute(conn, sql)
    catch e
        error("セキュアなテーブル作成に失敗しました: $e")
    end
end

function secure_table_exists(conn::DuckDB.DB, table_name::String)::Bool
    """
    テーブルの存在をセキュアにチェック
    """
    # テーブル名の検証
    validate_input(table_name, "table_name", 64)
    
    # 英数字とアンダースコアのみ許可
    if !occursin(r"^[a-zA-Z_][a-zA-Z0-9_]*$", table_name)
        throw(ArgumentError("不正なテーブル名です"))
    end
    
    sql = "SELECT COUNT(*) as count FROM information_schema.tables WHERE table_name = ?"
    
    try
        result = DuckDB.execute(conn, sql, [table_name])
        df = DataFrame(result)
        return df[1, :count] > 0
    catch e
        @warn "テーブル存在確認中にエラーが発生しました: $e"
        return false
    end
end

function secure_insert_stock(conn::DuckDB.DB, stock::Stock)
    """
    セキュアな在庫データ挿入
    """
    # 入力検証
    validate_input(stock.name, "name", 255)
    validate_input(stock.code, "code", 50)
    validate_input(stock.unit, "unit", 20)
    validate_input(stock.category, "category", 100)
    validate_input(stock.location, "location", 100)
    
    if stock.quantity < 0
        throw(ArgumentError("数量は0以上である必要があります"))
    end
    
    if stock.price < 0
        throw(ArgumentError("価格は0以上である必要があります"))
    end
    
    # サニタイズ
    sanitized_name = sanitize_string(stock.name)
    sanitized_code = sanitize_string(stock.code)
    sanitized_unit = sanitize_string(stock.unit)
    sanitized_category = sanitize_string(stock.category)
    sanitized_location = sanitize_string(stock.location)
    
    sql = """
    INSERT INTO stocks (id, name, code, quantity, unit, price, category, location, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    try
        DuckDB.execute(conn, sql, [
            stock.id, sanitized_name, sanitized_code, stock.quantity, sanitized_unit,
            stock.price, sanitized_category, sanitized_location, stock.created_at, stock.updated_at
        ])
    catch e
        error("セキュアな在庫データ挿入に失敗しました: $e")
    end
end

function secure_get_all_stocks(conn::DuckDB.DB)::Vector{Stock}
    """
    全在庫データをセキュアに取得
    """
    sql = "SELECT * FROM stocks ORDER BY id LIMIT 1000"  # 結果数制限
    
    try
        result = DuckDB.execute(conn, sql)
        df = DataFrame(result)
        
        stocks = Stock[]
        for row in eachrow(df)
            push!(stocks, Stock(
                row.id, row.name, row.code, row.quantity, row.unit,
                row.price, row.category, row.location, row.created_at, row.updated_at
            ))
        end
        
        return stocks
    catch e
        error("セキュアな在庫データ取得に失敗しました: $e")
    end
end

function secure_get_stock_by_id(conn::DuckDB.DB, id::Int64)::Union{Stock, Nothing}
    """
    IDによるセキュアな在庫データ取得
    """
    if id <= 0
        throw(ArgumentError("IDは正の整数である必要があります"))
    end
    
    sql = "SELECT * FROM stocks WHERE id = ? LIMIT 1"
    
    try
        result = DuckDB.execute(conn, sql, [id])
        df = DataFrame(result)
        
        if nrow(df) == 0
            return nothing
        end
        
        row = df[1, :]
        return Stock(
            row.id, row.name, row.code, row.quantity, row.unit,
            row.price, row.category, row.location, row.created_at, row.updated_at
        )
    catch e
        error("セキュアな在庫データ取得に失敗しました: $e")
    end
end

function secure_update_stock(conn::DuckDB.DB, stock::Stock)
    """
    セキュアな在庫データ更新
    """
    # 入力検証
    validate_input(stock.name, "name", 255)
    validate_input(stock.code, "code", 50)
    validate_input(stock.unit, "unit", 20)
    validate_input(stock.category, "category", 100)
    validate_input(stock.location, "location", 100)
    
    if stock.quantity < 0
        throw(ArgumentError("数量は0以上である必要があります"))
    end
    
    if stock.price < 0
        throw(ArgumentError("価格は0以上である必要があります"))
    end
    
    # サニタイズ
    sanitized_name = sanitize_string(stock.name)
    sanitized_code = sanitize_string(stock.code)
    sanitized_unit = sanitize_string(stock.unit)
    sanitized_category = sanitize_string(stock.category)
    sanitized_location = sanitize_string(stock.location)
    
    sql = """
    UPDATE stocks 
    SET name = ?, code = ?, quantity = ?, unit = ?, price = ?, 
        category = ?, location = ?, updated_at = ?
    WHERE id = ?
    """
    
    try
        DuckDB.execute(conn, sql, [
            sanitized_name, sanitized_code, stock.quantity, sanitized_unit, stock.price,
            sanitized_category, sanitized_location, stock.updated_at, stock.id
        ])
    catch e
        error("セキュアな在庫データ更新に失敗しました: $e")
    end
end

function secure_delete_stock(conn::DuckDB.DB, id::Int64)
    """
    セキュアな在庫データ削除
    """
    if id <= 0
        throw(ArgumentError("IDは正の整数である必要があります"))
    end
    
    sql = "DELETE FROM stocks WHERE id = ?"
    
    try
        DuckDB.execute(conn, sql, [id])
    catch e
        error("セキュアな在庫データ削除に失敗しました: $e")
    end
end

function secure_get_stocks_by_category(conn::DuckDB.DB, category::String)::Vector{Stock}
    """
    カテゴリによるセキュアな在庫データ取得
    """
    validate_input(category, "category", 100)
    sanitized_category = sanitize_string(category)
    
    sql = "SELECT * FROM stocks WHERE category = ? ORDER BY id LIMIT 500"
    
    try
        result = DuckDB.execute(conn, sql, [sanitized_category])
        df = DataFrame(result)
        
        stocks = Stock[]
        for row in eachrow(df)
            push!(stocks, Stock(
                row.id, row.name, row.code, row.quantity, row.unit,
                row.price, row.category, row.location, row.created_at, row.updated_at
            ))
        end
        
        return stocks
    catch e
        error("セキュアなカテゴリ別在庫データ取得に失敗しました: $e")
    end
end

function secure_get_out_of_stock_items(conn::DuckDB.DB)::Vector{Stock}
    """
    セキュアな在庫切れ商品取得
    """
    sql = "SELECT * FROM stocks WHERE quantity = 0 ORDER BY id LIMIT 500"
    
    try
        result = DuckDB.execute(conn, sql)
        df = DataFrame(result)
        
        stocks = Stock[]
        for row in eachrow(df)
            push!(stocks, Stock(
                row.id, row.name, row.code, row.quantity, row.unit,
                row.price, row.category, row.location, row.created_at, row.updated_at
            ))
        end
        
        return stocks
    catch e
        error("セキュアな在庫切れ商品取得に失敗しました: $e")
    end
end

function secure_get_low_stock_items(conn::DuckDB.DB, threshold::Int64)::Vector{Stock}
    """
    セキュアな低在庫商品取得
    """
    if threshold < 0
        throw(ArgumentError("閾値は0以上である必要があります"))
    end
    
    if threshold > 10000  # 異常に大きな値の防止
        throw(ArgumentError("閾値が大きすぎます"))
    end
    
    sql = "SELECT * FROM stocks WHERE quantity < ? ORDER BY quantity, id LIMIT 500"
    
    try
        result = DuckDB.execute(conn, sql, [threshold])
        df = DataFrame(result)
        
        stocks = Stock[]
        for row in eachrow(df)
            push!(stocks, Stock(
                row.id, row.name, row.code, row.quantity, row.unit,
                row.price, row.category, row.location, row.created_at, row.updated_at
            ))
        end
        
        return stocks
    catch e
        error("セキュアな低在庫商品取得に失敗しました: $e")
    end
end

function secure_begin_transaction(conn::DuckDB.DB)
    """
    セキュアなトランザクション開始
    """
    try
        DuckDB.execute(conn, "BEGIN TRANSACTION")
    catch e
        error("セキュアなトランザクション開始に失敗しました: $e")
    end
end

function secure_commit_transaction(conn::DuckDB.DB)
    """
    セキュアなトランザクションコミット
    """
    try
        DuckDB.execute(conn, "COMMIT")
    catch e
        error("セキュアなトランザクションコミットに失敗しました: $e")
    end
end

function secure_rollback_transaction(conn::DuckDB.DB)
    """
    セキュアなトランザクションロールバック
    """
    try
        DuckDB.execute(conn, "ROLLBACK")
    catch e
        error("セキュアなトランザクションロールバックに失敗しました: $e")
    end
end

end