module DuckDBConnection

using DuckDB
using DataFrames
using Dates
using ..StockModel

export db_connect, db_close, create_stock_table, table_exists,
       insert_stock, get_all_stocks, get_stock_by_id, update_stock, delete_stock,
       get_stocks_by_category, get_out_of_stock_items, get_low_stock_items,
       begin_transaction, commit_transaction, rollback_transaction,
       execute_query

function db_connect(db_path::String = ":memory:")::DuckDB.DB
    """
    DuckDBデータベースへの接続を確立する
    
    Args:
        db_path: データベースファイルのパス。デフォルトはインメモリ
    
    Returns:
        DuckDB.DB: データベース接続オブジェクト
    """
    try
        return DuckDB.DB(db_path)
    catch e
        error("データベース接続に失敗しました: $e")
    end
end

"""
任意のクエリを実行してDataFrameを返す（パラメータ化対応）
"""
function execute_query(conn::DuckDB.DB, sql::AbstractString, params::AbstractVector = Any[])::DataFrame
    try
        result = isempty(params) ? DuckDB.execute(conn, sql) : DuckDB.execute(conn, sql, params)
        return DataFrame(result)
    catch e
        error("クエリ実行に失敗しました: $e")
    end
end

function db_close(conn::DuckDB.DB)
    """
    データベース接続を閉じる
    
    Args:
        conn: データベース接続オブジェクト
    """
    try
        DuckDB.close(conn)
    catch e
        @warn "データベース接続の終了中にエラーが発生しました: $e"
    end
end

function create_stock_table(conn::DuckDB.DB)
    """
    在庫テーブルを作成する
    
    Args:
        conn: データベース接続オブジェクト
    """
    sql = """
    CREATE TABLE IF NOT EXISTS stocks (
        id INTEGER PRIMARY KEY,
        name VARCHAR NOT NULL,
        code VARCHAR UNIQUE NOT NULL,
        quantity INTEGER NOT NULL CHECK (quantity >= 0),
        unit VARCHAR NOT NULL,
        price DECIMAL(10,2) NOT NULL CHECK (price >= 0),
        category VARCHAR NOT NULL,
        location VARCHAR NOT NULL,
        created_at TIMESTAMP NOT NULL,
        updated_at TIMESTAMP NOT NULL
    )
    """
    
    try
        DuckDB.execute(conn, sql)
    catch e
        error("テーブル作成に失敗しました: $e")
    end
end

function table_exists(conn::DuckDB.DB, table_name::String)::Bool
    """
    指定されたテーブルが存在するかチェック
    
    Args:
        conn: データベース接続オブジェクト
        table_name: テーブル名
        
    Returns:
        Bool: テーブルが存在する場合はtrue
    """
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

function insert_stock(conn::DuckDB.DB, stock::Stock)
    """
    新しい在庫データを挿入する
    
    Args:
        conn: データベース接続オブジェクト
        stock: 在庫データ
    """
    sql = """
    INSERT INTO stocks (id, name, code, quantity, unit, price, category, location, created_at, updated_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """
    
    try
        DuckDB.execute(conn, sql, [
            stock.id, stock.name, stock.code, stock.quantity, stock.unit,
            stock.price, stock.category, stock.location, stock.created_at, stock.updated_at
        ])
    catch e
        error("在庫データの挿入に失敗しました: $e")
    end
end

function get_all_stocks(conn::DuckDB.DB)::Vector{Stock}
    """
    全ての在庫データを取得する
    
    Args:
        conn: データベース接続オブジェクト
        
    Returns:
        Vector{Stock}: 在庫データのベクター
    """
    sql = "SELECT * FROM stocks ORDER BY id"
    
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
        error("在庫データの取得に失敗しました: $e")
    end
end

function get_stock_by_id(conn::DuckDB.DB, id::Int64)::Union{Stock, Nothing}
    """
    IDによる在庫データの取得
    
    Args:
        conn: データベース接続オブジェクト
        id: 在庫ID
        
    Returns:
        Union{Stock, Nothing}: 在庫データまたはNothing
    """
    sql = "SELECT * FROM stocks WHERE id = ?"
    
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
        error("在庫データの取得に失敗しました: $e")
    end
end

function update_stock(conn::DuckDB.DB, stock::Stock)
    """
    在庫データを更新する
    
    Args:
        conn: データベース接続オブジェクト
        stock: 更新する在庫データ
    """
    sql = """
    UPDATE stocks 
    SET name = ?, code = ?, quantity = ?, unit = ?, price = ?, 
        category = ?, location = ?, updated_at = ?
    WHERE id = ?
    """
    
    try
        DuckDB.execute(conn, sql, [
            stock.name, stock.code, stock.quantity, stock.unit, stock.price,
            stock.category, stock.location, stock.updated_at, stock.id
        ])
    catch e
        error("在庫データの更新に失敗しました: $e")
    end
end

function delete_stock(conn::DuckDB.DB, id::Int64)
    """
    在庫データを削除する
    
    Args:
        conn: データベース接続オブジェクト
        id: 削除する在庫ID
    """
    sql = "DELETE FROM stocks WHERE id = ?"
    
    try
        DuckDB.execute(conn, sql, [id])
    catch e
        error("在庫データの削除に失敗しました: $e")
    end
end

function get_stocks_by_category(conn::DuckDB.DB, category::String)::Vector{Stock}
    """
    カテゴリによる在庫データの取得
    
    Args:
        conn: データベース接続オブジェクト
        category: カテゴリ名
        
    Returns:
        Vector{Stock}: 指定カテゴリの在庫データ
    """
    sql = "SELECT * FROM stocks WHERE category = ? ORDER BY id"
    
    try
        result = DuckDB.execute(conn, sql, [category])
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
        error("カテゴリ別在庫データの取得に失敗しました: $e")
    end
end

function get_out_of_stock_items(conn::DuckDB.DB)::Vector{Stock}
    """
    在庫切れ商品を取得する
    
    Args:
        conn: データベース接続オブジェクト
        
    Returns:
        Vector{Stock}: 在庫切れ商品のベクター
    """
    sql = "SELECT * FROM stocks WHERE quantity = 0 ORDER BY id"
    
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
        error("在庫切れ商品の取得に失敗しました: $e")
    end
end

function get_low_stock_items(conn::DuckDB.DB, threshold::Int64)::Vector{Stock}
    """
    低在庫商品を取得する
    
    Args:
        conn: データベース接続オブジェクト
        threshold: 低在庫の閾値
        
    Returns:
        Vector{Stock}: 低在庫商品のベクター
    """
    sql = "SELECT * FROM stocks WHERE quantity < ? ORDER BY quantity, id"
    
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
        error("低在庫商品の取得に失敗しました: $e")
    end
end

function begin_transaction(conn::DuckDB.DB)
    """
    トランザクションを開始する
    
    Args:
        conn: データベース接続オブジェクト
    """
    try
        DuckDB.execute(conn, "BEGIN TRANSACTION")
    catch e
        error("トランザクション開始に失敗しました: $e")
    end
end

function commit_transaction(conn::DuckDB.DB)
    """
    トランザクションをコミットする
    
    Args:
        conn: データベース接続オブジェクト
    """
    try
        DuckDB.execute(conn, "COMMIT")
    catch e
        error("トランザクションコミットに失敗しました: $e")
    end
end

function rollback_transaction(conn::DuckDB.DB)
    """
    トランザクションをロールバックする
    
    Args:
        conn: データベース接続オブジェクト
    """
    try
        DuckDB.execute(conn, "ROLLBACK")
    catch e
        error("トランザクションロールバックに失敗しました: $e")
    end
end

end
