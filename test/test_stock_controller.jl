using Test
using HTTP
using JSON3
using DataFrames
using Dates
using Genie

include("../src/web/controllers/StockController.jl")
include("../src/models/Stock.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")

@testset "StockController Tests" begin
    # テスト用DBを初期化
    test_db_path = "data/test_inventory.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end
    
    @testset "index - 全在庫一覧取得" begin
        # テストデータを準備（コントローラー経由で作成）
        _ = StockController.create(Dict(
            "product_code" => "TEST001",
            "product_name" => "テスト商品1",
            "category" => "テスト",
            "quantity" => 100,
            "unit" => "個",
            "price" => 1000
        ))
        
        # コントローラーメソッドを呼び出し
        response = StockController.index()
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test length(data) >= 1
        @test data[1][:product_code] == "TEST001"
    end
    
    @testset "show - 特定在庫取得" begin
        # テストデータを作成（コントローラー経由）
        resp = StockController.create(Dict(
            "product_code" => "TEST002",
            "product_name" => "テスト商品2",
            "category" => "テスト",
            "quantity" => 50,
            "unit" => "個",
            "price" => 500
        ))
        created = JSON3.read(String(resp.body))
        
        # コントローラーメソッドを呼び出し
        response = StockController.show(created[:id])
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:product_code] == "TEST002"
    end
    
    @testset "create - 新規在庫追加" begin
        # リクエストデータ
        payload = Dict(
            "product_code" => "TEST003",
            "product_name" => "テスト商品3",
            "category" => "テスト",
            "quantity" => 200,
            "unit" => "個",
            "price" => 2000
        )
        
        # コントローラーメソッドを呼び出し
        response = StockController.create(payload)
        
        # レスポンスの検証
        @test response.status == 201
        data = JSON3.read(String(response.body))
        @test data[:product_code] == "TEST003"
        @test data[:message] == "在庫が正常に作成されました"
    end
    
    @testset "update - 在庫更新" begin
        # テストデータを作成
        resp = StockController.create(Dict(
            "product_code" => "TEST004",
            "product_name" => "テスト商品4",
            "category" => "テスト",
            "quantity" => 75,
            "unit" => "個",
            "price" => 750
        ))
        stock = JSON3.read(String(resp.body))
        
        # 更新データ
        update_data = Dict(
            "quantity" => 150,
            "price" => 1500
        )
        
        # コントローラーメソッドを呼び出し
        response = StockController.update(stock[:id], update_data)
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:quantity] == 150
        @test data[:price] == 1500
        @test data[:message] == "在庫が正常に更新されました"
    end
    
    @testset "destroy - 在庫削除" begin
        # テストデータを作成
        resp = StockController.create(Dict(
            "product_code" => "TEST005",
            "product_name" => "テスト商品5",
            "category" => "テスト",
            "quantity" => 25,
            "unit" => "個",
            "price" => 250
        ))
        stock = JSON3.read(String(resp.body))
        
        # コントローラーメソッドを呼び出し
        response = StockController.destroy(stock[:id])
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:message] == "在庫が正常に削除されました"
        
        # 削除確認（404）
        resp2 = StockController.show(stock[:id])
        @test resp2.status == 404
    end
    
    @testset "エラーハンドリング" begin
        # 存在しないIDでの取得
        response = StockController.show(99999)
        @test response.status == 404
        
        # 不正なデータでの作成
        invalid_payload = Dict("product_code" => "")
        response = StockController.create(invalid_payload)
        @test response.status == 400
    end
    
    # テスト後のクリーンアップ
    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
