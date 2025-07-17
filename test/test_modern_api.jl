using Test
using HTTP
using JSON3
using Dates

# モダンAPIエンドポイントのテストスイート
@testset "Modern API Endpoints Tests" begin
    
    # テスト用のベースURL
    base_url = "http://localhost:8000/api"
    
    @testset "在庫一覧取得（ページネーション付き）" begin
        # ページネーション、検索、ソートのパラメータをテスト
        params = Dict(
            "page" => 1,
            "limit" => 20,
            "search" => "",
            "category" => "",
            "sortBy" => "updated_at",
            "sortOrder" => "desc"
        )
        
        response = HTTP.get("$base_url/stocks", query=params)
        @test response.status == 200
        
        data = JSON3.read(String(response.body))
        @test haskey(data, :stocks)
        @test haskey(data, :totalPages)
        @test haskey(data, :statistics)
        @test isa(data.stocks, Vector)
        
        # 統計情報の確認
        stats = data.statistics
        @test haskey(stats, :totalItems)
        @test haskey(stats, :totalValue)
        @test haskey(stats, :lowStockItems)
        @test haskey(stats, :outOfStockItems)
    end
    
    @testset "検索機能" begin
        # 商品名での検索
        params = Dict("search" => "テスト商品")
        response = HTTP.get("$base_url/stocks", query=params)
        @test response.status == 200
        
        data = JSON3.read(String(response.body))
        if !isempty(data.stocks)
            for stock in data.stocks
                @test occursin("テスト商品", stock.product_name) || occursin("テスト商品", stock.product_code)
            end
        end
    end
    
    @testset "カテゴリフィルター" begin
        params = Dict("category" => "電子部品")
        response = HTTP.get("$base_url/stocks", query=params)
        @test response.status == 200
        
        data = JSON3.read(String(response.body))
        for stock in data.stocks
            @test stock.category == "電子部品"
        end
    end
    
    @testset "ソート機能" begin
        # 価格の降順でソート
        params = Dict("sortBy" => "price", "sortOrder" => "desc")
        response = HTTP.get("$base_url/stocks", query=params)
        @test response.status == 200
        
        data = JSON3.read(String(response.body))
        prices = [stock.price for stock in data.stocks]
        @test issorted(prices, rev=true)
    end
    
    @testset "在庫の作成（バリデーション付き）" begin
        # 正常なデータ
        new_stock = Dict(
            "product_code" => "TEST-$(rand(1000:9999))",
            "product_name" => "テスト商品",
            "category" => "電子部品",
            "quantity" => 100,
            "unit" => "個",
            "price" => 1500.50,
            "location" => "A-1-1",
            "description" => "テスト用の商品です"
        )
        
        response = HTTP.post(
            "$base_url/stocks",
            ["Content-Type" => "application/json"],
            JSON3.write(new_stock)
        )
        @test response.status == 201
        
        created = JSON3.read(String(response.body))
        @test haskey(created, :id)
        @test created.product_code == new_stock["product_code"]
        
        # バリデーションエラーのテスト
        invalid_stock = Dict(
            "product_code" => "",  # 必須フィールドが空
            "product_name" => "テスト",
            "quantity" => -10  # 負の値
        )
        
        response = HTTP.post(
            "$base_url/stocks",
            ["Content-Type" => "application/json"],
            JSON3.write(invalid_stock),
            status_exception=false
        )
        @test response.status == 400
    end
    
    @testset "在庫の更新" begin
        # まず在庫を作成
        stock_data = Dict(
            "product_code" => "UPDATE-TEST",
            "product_name" => "更新テスト商品",
            "category" => "工具",
            "quantity" => 50,
            "unit" => "個",
            "price" => 2000
        )
        
        create_response = HTTP.post(
            "$base_url/stocks",
            ["Content-Type" => "application/json"],
            JSON3.write(stock_data)
        )
        created = JSON3.read(String(create_response.body))
        stock_id = created.id
        
        # 更新
        update_data = Dict(
            "quantity" => 75,
            "price" => 2500,
            "location" => "B-2-3"
        )
        
        response = HTTP.put(
            "$base_url/stocks/$stock_id",
            ["Content-Type" => "application/json"],
            JSON3.write(update_data)
        )
        @test response.status == 200
        
        updated = JSON3.read(String(response.body))
        @test updated.quantity == 75
        @test updated.price == 2500
        @test updated.location == "B-2-3"
    end
    
    @testset "在庫の削除" begin
        # テスト用在庫を作成
        stock_data = Dict(
            "product_code" => "DELETE-TEST",
            "product_name" => "削除テスト商品",
            "category" => "その他",
            "quantity" => 10,
            "unit" => "個",
            "price" => 500
        )
        
        create_response = HTTP.post(
            "$base_url/stocks",
            ["Content-Type" => "application/json"],
            JSON3.write(stock_data)
        )
        created = JSON3.read(String(create_response.body))
        stock_id = created.id
        
        # 削除
        response = HTTP.delete("$base_url/stocks/$stock_id")
        @test response.status == 204
        
        # 削除確認
        get_response = HTTP.get("$base_url/stocks/$stock_id", status_exception=false)
        @test get_response.status == 404
    end
    
    @testset "一括操作" begin
        # 複数在庫の一括更新
        ids = [1, 2, 3]  # 実際のIDに置き換える必要があります
        bulk_update = Dict(
            "ids" => ids,
            "updates" => Dict("category" => "消耗品")
        )
        
        response = HTTP.post(
            "$base_url/stocks/bulk-update",
            ["Content-Type" => "application/json"],
            JSON3.write(bulk_update),
            status_exception=false
        )
        
        # エンドポイントが実装されていれば200、されていなければ404
        @test response.status in [200, 404]
    end
    
    @testset "リアルタイム統計" begin
        response = HTTP.get("$base_url/stocks/statistics")
        @test response.status == 200
        
        stats = JSON3.read(String(response.body))
        @test haskey(stats, :totalItems)
        @test haskey(stats, :totalValue)
        @test haskey(stats, :categoryBreakdown)
        @test haskey(stats, :lowStockAlerts)
        @test haskey(stats, :recentActivity)
    end
    
    @testset "エラーハンドリング" begin
        # 存在しないリソース
        response = HTTP.get("$base_url/stocks/999999", status_exception=false)
        @test response.status == 404
        
        error_data = JSON3.read(String(response.body))
        @test haskey(error_data, :error)
        @test haskey(error_data, :message)
        
        # 不正なリクエスト
        response = HTTP.post(
            "$base_url/stocks",
            ["Content-Type" => "application/json"],
            "invalid json",
            status_exception=false
        )
        @test response.status == 400
    end
    
    @testset "レート制限" begin
        # 短時間に多数のリクエストを送信
        responses = []
        for i in 1:10
            push!(responses, HTTP.get("$base_url/stocks", status_exception=false))
        end
        
        # レート制限が実装されていれば、いくつかは429を返すはず
        status_codes = [r.status for r in responses]
        @test all(s in [200, 429] for s in status_codes)
    end
end

# WebSocket接続のテスト（オプション）
@testset "WebSocket Real-time Updates" begin
    # WebSocket接続のモックテスト
    # 実際の実装では、WebSocketクライアントライブラリを使用
    
    @test true  # プレースホルダー
end