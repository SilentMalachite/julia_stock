using Test
using HTTP
using JSON3
using DataFrames
using Dates

include("../src/InventorySystem.jl")
using .InventorySystem

@testset "Integration Tests" begin
    # テスト用のデータベース設定
    test_db_path = "data/test_integration.duckdb"
    
    # データベースを初期化
    InventorySystem.DuckDBConnection.initialize_database(test_db_path)
    
    @testset "エンドツーエンド在庫管理フロー" begin
        # 1. 新規在庫を作成
        create_payload = Dict(
            "product_code" => "INT001",
            "product_name" => "統合テスト商品",
            "category" => "テスト",
            "quantity" => 100,
            "unit" => "個",
            "price" => 1000
        )
        
        created_stock = InventorySystem.StockModel.create(create_payload)
        @test created_stock.product_code == "INT001"
        @test created_stock.quantity == 100
        
        # 2. 在庫を検索
        found_stock = InventorySystem.StockModel.find(created_stock.id)
        @test found_stock.product_name == "統合テスト商品"
        
        # 3. 在庫を更新
        update_data = Dict("quantity" => 150, "price" => 1200)
        updated_stock = InventorySystem.StockModel.update(created_stock.id, update_data)
        @test updated_stock.quantity == 150
        @test updated_stock.price == 1200
        
        # 4. カテゴリで検索
        stocks_by_category = InventorySystem.StockModel.find_by_category("テスト")
        @test length(stocks_by_category) >= 1
        @test any(s -> s.id == created_stock.id, stocks_by_category)
        
        # 5. 在庫を削除
        InventorySystem.StockModel.delete(created_stock.id)
        @test_throws Exception InventorySystem.StockModel.find(created_stock.id)
    end
    
    @testset "Excel連携フロー" begin
        # 1. テストデータを作成
        test_stocks = [
            Dict(
                "product_code" => "EXC001",
                "product_name" => "Excel商品1",
                "category" => "Excel",
                "quantity" => 50,
                "unit" => "個",
                "price" => 500
            ),
            Dict(
                "product_code" => "EXC002",
                "product_name" => "Excel商品2",
                "category" => "Excel",
                "quantity" => 75,
                "unit" => "個",
                "price" => 750
            )
        ]
        
        for stock_data in test_stocks
            InventorySystem.StockModel.create(stock_data)
        end
        
        # 2. Excelにエクスポート
        export_file = "test_export.xlsx"
        InventorySystem.ExcelHandler.export_to_excel(export_file)
        @test isfile(export_file)
        
        # 3. データベースをクリア
        for stock in InventorySystem.StockModel.find_by_category("Excel")
            InventorySystem.StockModel.delete(stock.id)
        end
        
        # 4. Excelからインポート
        imported_count = InventorySystem.ExcelHandler.import_from_excel(export_file)
        @test imported_count >= 2
        
        # 5. インポートされたデータを確認
        imported_stocks = InventorySystem.StockModel.find_by_category("Excel")
        @test length(imported_stocks) >= 2
        
        # クリーンアップ
        rm(export_file, force=true)
    end
    
    @testset "認証と権限管理フロー" begin
        # 1. ユーザーを作成
        user = InventorySystem.AuthenticationSystem.create_user(
            "test_user",
            "test_password",
            "user"
        )
        @test user.username == "test_user"
        @test user.role == "user"
        
        # 2. ログイン
        auth_user = InventorySystem.AuthenticationSystem.authenticate_user(
            "test_user",
            "test_password"
        )
        @test auth_user !== nothing
        @test auth_user.username == "test_user"
        
        # 3. 権限チェック
        @test InventorySystem.AuthenticationSystem.has_permission(user, "read")
        @test !InventorySystem.AuthenticationSystem.has_permission(user, "admin")
        
        # 4. 管理者ユーザーを作成
        admin = InventorySystem.AuthenticationSystem.create_user(
            "admin_user",
            "admin_password",
            "admin"
        )
        @test InventorySystem.AuthenticationSystem.has_permission(admin, "admin")
    end
    
    @testset "エラーハンドリングフロー" begin
        # 1. 存在しないIDでの操作
        @test_throws Exception InventorySystem.StockModel.find(99999)
        @test_throws Exception InventorySystem.StockModel.update(99999, Dict())
        @test_throws Exception InventorySystem.StockModel.delete(99999)
        
        # 2. 不正なデータでの作成
        invalid_data = Dict("product_code" => "")  # 必須フィールドが空
        @test_throws Exception InventorySystem.StockModel.create(invalid_data)
        
        # 3. 不正なファイルでのExcelインポート
        @test_throws Exception InventorySystem.ExcelHandler.import_from_excel("non_existent.xlsx")
    end
    
    @testset "パフォーマンステスト" begin
        # 大量データの処理テスト
        start_time = time()
        
        # 100件のデータを作成
        for i in 1:100
            InventorySystem.StockModel.create(Dict(
                "product_code" => "PERF$(lpad(i, 3, '0'))",
                "product_name" => "パフォーマンステスト商品$i",
                "category" => "パフォーマンス",
                "quantity" => rand(1:1000),
                "unit" => "個",
                "price" => rand(100:10000)
            ))
        end
        
        create_time = time() - start_time
        @test create_time < 10.0  # 10秒以内で完了すること
        
        # 全件取得のパフォーマンス
        start_time = time()
        all_stocks = InventorySystem.StockModel.all()
        fetch_time = time() - start_time
        @test fetch_time < 1.0  # 1秒以内で完了すること
        @test length(all_stocks) >= 100
        
        # クリーンアップ
        for stock in InventorySystem.StockModel.find_by_category("パフォーマンス")
            InventorySystem.StockModel.delete(stock.id)
        end
    end
    
    # テスト後のクリーンアップ
    rm(test_db_path, force=true)
end