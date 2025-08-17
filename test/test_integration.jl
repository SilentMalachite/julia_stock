using Test
using JSON3
using DataFrames
using Dates

include("../src/web/controllers/StockController.jl")
include("../src/excel/ExcelHandler.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")
include("../src/auth/AuthenticationSystem.jl")

@testset "Integration-like Flow (current spec)" begin
    # DB初期化
    test_db_path = "data/test_integration.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end

    @testset "在庫の作成→取得→更新→削除" begin
        # 作成
        resp = StockController.create(Dict("product_code"=>"INT001","product_name"=>"統合テスト商品","category"=>"テスト","quantity"=>100,"unit"=>"個","price"=>1000.0,"location"=>"I-1"))
        @test resp.status == 201
        obj = JSON3.read(String(resp.body)); id = obj[:id]

        # 取得
        rshow = StockController.show(id); @test rshow.status == 200

        # 更新
        rupd = StockController.update(id, Dict("quantity"=>150, "price"=>1200.0)); @test rupd.status == 200
        u = JSON3.read(String(rupd.body)); @test u[:quantity] == 150; @test u[:price] == 1200.0

        # カテゴリで確認
        conn = ConnectionPool.get_connection_from_pool(); try
            lst = SecureDuckDBConnection.secure_get_stocks_by_category(conn, "テスト")
            @test any(s -> s.id == id, lst)
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end

        # 削除
        rdel = StockController.destroy(id); @test rdel.status == 200
        r404 = StockController.show(id); @test r404.status == 404
    end

    @testset "Excel エクスポート→DBクリア→インポート" begin
        # 2件作成
        _ = StockController.create(Dict("product_code"=>"EXC001","product_name"=>"Excel商品1","category"=>"Excel","quantity"=>50,"unit"=>"個","price"=>500.0,"location"=>"E-1"))
        _ = StockController.create(Dict("product_code"=>"EXC002","product_name"=>"Excel商品2","category"=>"Excel","quantity"=>75,"unit"=>"個","price"=>750.0,"location"=>"E-2"))
        # エクスポート
        file = "test_export.xlsx"; @test_nowarn ExcelHandler.export_to_excel(file)
        @test isfile(file)
        # DBクリア
        conn = ConnectionPool.get_connection_from_pool(); try
            stocks = SecureDuckDBConnection.secure_get_all_stocks(conn)
            for s in stocks
                SecureDuckDBConnection.secure_delete_stock(conn, s.id)
            end
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end
        # インポート
        cnt = ExcelHandler.import_from_excel(file); @test cnt >= 2
        rm(file, force=true)
    end

    @testset "認証と権限" begin
        # 認証DB初期化
        AuthenticationSystem.init_auth_database("data/test_auth.db")
        # 強力なパスワードとメールで作成
        usr = AuthenticationSystem.create_user("test_user","StrongPass123!","test@example.com","user")
        @test AuthenticationSystem.has_permission(usr, "view_all_stocks") == true
        @test AuthenticationSystem.authenticate_user("test_user","StrongPass123!") !== nothing
    end

    @testset "エラーフロー" begin
        # 不正データでの作成（400）
        rbad = StockController.create(Dict("product_code"=>""))
        @test rbad.status == 400
        # 存在しないID
        rnf = StockController.show(999999)
        @test rnf.status == 404
        # 不正なExcelパス
        @test_throws Exception ExcelHandler.import_from_excel("non_existent.xlsx")
    end

    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
