using Test
using Dates

include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")
include("../src/models/Stock.jl")

@testset "Security Tests (current spec)" begin
    test_db_path = "data/test_security.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end

    @testset "入力検証・サニタイズ" begin
        conn = ConnectionPool.get_connection_from_pool()
        try
            # 正常データ
            s = StockModel.Stock(1, "テスト商品", "TEST001", 10, "個", 1000.0, "カテゴリ", "L-1", now(), now())
            @test_nowarn SecureDuckDBConnection.secure_insert_stock(conn, s)

            # 危険なパターンはvalidate_inputで弾かれる
            s_bad = StockModel.Stock(2, "<script>", "DROP1", 0, "個", 0.0, "カテゴリ", "L-2", now(), now())
            @test_throws Exception SecureDuckDBConnection.secure_insert_stock(conn, s_bad)

            # カテゴリ検索に危険文字列
            @test_throws Exception SecureDuckDBConnection.secure_get_stocks_by_category(conn, "'; DROP TABLE stocks; --")
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end
    end

    @testset "低在庫/在庫切れクエリ" begin
        conn = ConnectionPool.get_connection_from_pool()
        try
            @test_nowarn SecureDuckDBConnection.secure_get_low_stock_items(conn, 10)
            @test_nowarn SecureDuckDBConnection.secure_get_out_of_stock_items(conn)
            @test_throws Exception SecureDuckDBConnection.secure_get_low_stock_items(conn, -1)
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end
    end

    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
