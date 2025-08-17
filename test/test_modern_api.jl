using Test
using JSON3
using Dates

include("../src/web/controllers/ModernStockController.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")

@testset "Modern API Unit-like Tests" begin
    # DB初期化
    test_db_path = "data/test_inventory_modern.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end

    @testset "作成と一覧・検索・ソート" begin
        # 作成
        s1 = Dict("product_code"=>"T1001","product_name"=>"テスト商品A","category"=>"電子","quantity"=>10,"unit"=>"個","price"=>1000.0,"location"=>"A-1")
        s2 = Dict("product_code"=>"T1002","product_name"=>"テスト商品B","category"=>"電子","quantity"=>0,"unit"=>"個","price"=>500.0,"location"=>"A-2")
        r1 = ModernStockController.create_with_validation(s1); @test r1.status == 201
        r2 = ModernStockController.create_with_validation(s2); @test r2.status == 201

        # 一覧
        resp = ModernStockController.index_with_pagination(Dict("page"=>1,"limit"=>20))
        @test resp.status == 200
        data = JSON3.read(String(resp.body))
        @test haskey(data, :stocks)
        @test data.totalItems >= 2

        # 検索
        resp2 = ModernStockController.index_with_pagination(Dict("search"=>"テスト商品A"))
        @test resp2.status == 200
        d2 = JSON3.read(String(resp2.body))
        if !isempty(d2.stocks)
            for st in d2.stocks
                @test occursin("テスト商品", st.product_name)
            end
        end

        # ソート
        resp3 = ModernStockController.index_with_pagination(Dict("sortBy"=>"price","sortOrder"=>"desc"))
        @test resp3.status == 200
        d3 = JSON3.read(String(resp3.body))
        prices = [st.price for st in d3.stocks]
        @test issorted(prices, rev=true)
    end

    @testset "更新と削除・統計" begin
        # 1件作成
        r = ModernStockController.create_with_validation(Dict("product_code"=>"T2001","product_name"=>"更新対象","category"=>"工具","quantity"=>5,"unit"=>"個","price"=>2000.0,"location"=>"B-1"))
        obj = JSON3.read(String(r.body))
        id = obj[:id]

        # 更新
        ur = ModernStockController.update_with_validation(id, Dict("quantity"=>8,"price"=>2500.0))
        @test ur.status == 200
        u = JSON3.read(String(ur.body))
        @test u[:quantity] == 8
        @test u[:price] == 2500.0

        # 統計
        sr = ModernStockController.detailed_statistics()
        @test sr.status == 200

        # 削除
        dr = ModernStockController.destroy(id)
        @test dr.status == 200
    end

    # 一括更新
    @testset "一括更新" begin
        ids = Int[]
        for i in 1:3
            r = ModernStockController.create_with_validation(Dict("product_code"=>"BULK$(1000+i)","product_name"=>"一括$i","category"=>"消耗","quantity"=>i,"unit"=>"個","price"=>10.0*i,"location"=>"C-$i"))
            obj = JSON3.read(String(r.body)); push!(ids, obj[:id])
        end
        br = ModernStockController.bulk_update(Dict("ids"=>ids, "updates"=>Dict("category"=>"更新後")))
        @test br.status == 200
        bd = JSON3.read(String(br.body))
        @test bd[:updated_count] == 3
    end

    # 後片付け
    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
