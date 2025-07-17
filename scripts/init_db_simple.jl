#!/usr/bin/env julia

# 簡単なデータベース初期化スクリプト
using Pkg
Pkg.activate(".")

using DuckDB
using DataFrames
using Dates

println("データベースの初期化を開始します...")

# データベースファイルの作成
db_path = "data/inventory.db"
mkpath(dirname(db_path))

# 既存のデータベースファイルを削除（クリーンスタート）
if isfile(db_path)
    rm(db_path)
    println("既存のデータベースファイルを削除しました")
end

# データベース接続
conn = DBInterface.connect(DuckDB.DB, db_path)
println("データベースに接続しました: $db_path")

# テーブル作成
create_table_query = """
CREATE TABLE IF NOT EXISTS stocks (
    id INTEGER PRIMARY KEY,
    product_code VARCHAR NOT NULL UNIQUE,
    product_name VARCHAR NOT NULL,
    category VARCHAR NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    unit VARCHAR NOT NULL DEFAULT '個',
    price DECIMAL(10, 2) NOT NULL DEFAULT 0.00,
    location VARCHAR,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
)
"""

DuckDB.execute(conn, create_table_query)
println("✓ stocksテーブルを作成しました")

# インデックス作成
DuckDB.execute(conn, "CREATE INDEX IF NOT EXISTS idx_product_code ON stocks(product_code)")
DuckDB.execute(conn, "CREATE INDEX IF NOT EXISTS idx_category ON stocks(category)")
DuckDB.execute(conn, "CREATE INDEX IF NOT EXISTS idx_updated_at ON stocks(updated_at)")
println("✓ インデックスを作成しました")

# サンプルデータの挿入
sample_data = [
    ("ELEC-001", "抵抗器 10kΩ", "電子部品", 500, "個", 10.0, "A-1-1", "1/4W 炭素皮膜抵抗"),
    ("ELEC-002", "コンデンサ 100μF", "電子部品", 200, "個", 50.0, "A-1-2", "電解コンデンサ 25V"),
    ("MECH-001", "ボルト M6x20", "機械部品", 1000, "本", 5.0, "B-2-1", "六角ボルト ステンレス"),
    ("MECH-002", "ナット M6", "機械部品", 1500, "個", 3.0, "B-2-2", "六角ナット ステンレス"),
    ("TOOL-001", "ドライバー +2", "工具", 10, "本", 500.0, "C-3-1", "プラスドライバー"),
    ("CONS-001", "はんだ 0.8mm", "消耗品", 20, "巻", 1200.0, "D-4-1", "鉛フリーはんだ"),
    ("CONS-002", "フラックス", "消耗品", 5, "個", 800.0, "D-4-2", "ロジン系フラックス")
]

for data in sample_data
    insert_query = """
    INSERT INTO stocks (product_code, product_name, category, quantity, unit, price, location, description)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """
    DuckDB.execute(conn, insert_query, data)
end

println("✓ サンプルデータを挿入しました（$(length(sample_data))件）")

# データ確認
result = DuckDB.execute(conn, "SELECT COUNT(*) as count FROM stocks")
count = first(result).count
println("\n現在の在庫データ数: $count 件")

# テーブル情報表示
result = DuckDB.execute(conn, "SELECT * FROM stocks LIMIT 5")
df = DataFrame(result)
println("\nサンプルデータ（最初の5件）:")
println(df)

# 接続を閉じる
DBInterface.close!(conn)
println("\nデータベースの初期化が完了しました！")