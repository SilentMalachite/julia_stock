using Test
using HTTP
using JSON3
using DataFrames
using Dates
using Genie

include("../src/web/controllers/StockController.jl")
include("../src/models/Stock.jl")
include("../src/database/DuckDBConnection.jl")

@testset "StockController Tests" begin
    # テスト用のデータベース接続を設定
    test_db_path = "data/test_inventory.duckdb"
    DuckDBConnection.initialize_database(test_db_path)
    
    @testset "index - 全在庫一覧取得" begin
        # テストデータを準備
        Stock.create(Dict(
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
        # テストデータを作成
        stock = Stock.create(Dict(
            "product_code" => "TEST002",
            "product_name" => "テスト商品2",
            "category" => "テスト",
            "quantity" => 50,
            "unit" => "個",
            "price" => 500
        ))
        
        # コントローラーメソッドを呼び出し
        response = StockController.show(stock.id)
        
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
        stock = Stock.create(Dict(
            "product_code" => "TEST004",
            "product_name" => "テスト商品4",
            "category" => "テスト",
            "quantity" => 75,
            "unit" => "個",
            "price" => 750
        ))
        
        # 更新データ
        update_data = Dict(
            "quantity" => 150,
            "price" => 1500
        )
        
        # コントローラーメソッドを呼び出し
        response = StockController.update(stock.id, update_data)
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:quantity] == 150
        @test data[:price] == 1500
        @test data[:message] == "在庫が正常に更新されました"
    end
    
    @testset "destroy - 在庫削除" begin
        # テストデータを作成
        stock = Stock.create(Dict(
            "product_code" => "TEST005",
            "product_name" => "テスト商品5",
            "category" => "テスト",
            "quantity" => 25,
            "unit" => "個",
            "price" => 250
        ))
        
        # コントローラーメソッドを呼び出し
        response = StockController.destroy(stock.id)
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:message] == "在庫が正常に削除されました"
        
        # 削除確認
        @test_throws Exception Stock.find(stock.id)
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
    rm(test_db_path, force=true)
end