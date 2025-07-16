using Test
using DuckDB
using DataFrames
using Dates

# 必要な関数をインポート
using .InventorySystem: Stock, db_connect, db_close, create_stock_table, table_exists,
                       insert_stock, get_all_stocks, get_stock_by_id, update_stock, 
                       delete_stock, get_stocks_by_category, get_out_of_stock_items,
                       get_low_stock_items, begin_transaction, commit_transaction, 
                       rollback_transaction

@testset "DuckDB Connection Tests" begin
    
    @testset "データベース接続" begin
        # テスト: DuckDBへの接続が正常に行えること
        @test_nowarn db_connect()
        
        # テスト: データベース接続が有効であること
        conn = db_connect()
        @test conn !== nothing
        @test typeof(conn) == DuckDB.DB
        
        # 接続を閉じる
        @test_nowarn db_close(conn)
    end
    
    @testset "テーブル作成" begin
        conn = db_connect()
        
        # テスト: 在庫テーブルが正常に作成できること
        @test_nowarn create_stock_table(conn)
        
        # テスト: テーブルが存在することを確認
        @test table_exists(conn, "stocks")
        
        db_close(conn)
    end
    
    @testset "データ挿入・取得" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト用データ
        test_stock = Stock(
            1,
            "テスト商品",
            "TEST001",
            100,
            "個",
            1000.0,
            "テストカテゴリ",
            "A-1-1",
            now(),
            now()
        )
        
        # テスト: 在庫データの挿入
        @test_nowarn insert_stock(conn, test_stock)
        
        # テスト: 在庫データの取得
        stocks = get_all_stocks(conn)
        @test length(stocks) == 1
        @test stocks[1].name == "テスト商品"
        @test stocks[1].code == "TEST001"
        
        # テスト: IDによる在庫データの取得
        stock = get_stock_by_id(conn, 1)
        @test stock !== nothing
        @test stock.name == "テスト商品"
        
        # テスト: 存在しないIDでの取得
        @test get_stock_by_id(conn, 999) === nothing
        
        db_close(conn)
    end
    
    @testset "データ更新・削除" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト用データを挿入
        test_stock = Stock(
            1,
            "テスト商品",
            "TEST001",
            100,
            "個",
            1000.0,
            "テストカテゴリ",
            "A-1-1",
            now(),
            now()
        )
        insert_stock(conn, test_stock)
        
        # テスト: 在庫データの更新
        updated_stock = Stock(
            1,
            "更新されたテスト商品",
            "TEST001",
            150,
            "個",
            1200.0,
            "テストカテゴリ",
            "A-1-1",
            test_stock.created_at,
            now()
        )
        
        @test_nowarn update_stock(conn, updated_stock)
        
        # 更新確認
        stock = get_stock_by_id(conn, 1)
        @test stock.name == "更新されたテスト商品"
        @test stock.quantity == 150
        @test stock.price == 1200.0
        
        # テスト: 在庫データの削除
        @test_nowarn delete_stock(conn, 1)
        
        # 削除確認
        @test get_stock_by_id(conn, 1) === nothing
        stocks = get_all_stocks(conn)
        @test length(stocks) == 0
        
        db_close(conn)
    end
    
    @testset "検索・フィルタリング" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト用データを複数挿入
        stocks = [
            Stock(1, "商品A", "A001", 100, "個", 1000.0, "カテゴリ1", "A-1-1", now(), now()),
            Stock(2, "商品B", "B001", 50, "個", 2000.0, "カテゴリ2", "A-1-2", now(), now()),
            Stock(3, "商品C", "C001", 0, "個", 1500.0, "カテゴリ1", "A-2-1", now(), now())
        ]
        
        for stock in stocks
            insert_stock(conn, stock)
        end
        
        # テスト: カテゴリによる検索
        category1_stocks = get_stocks_by_category(conn, "カテゴリ1")
        @test length(category1_stocks) == 2
        
        # テスト: 在庫切れ商品の検索
        out_of_stock = get_out_of_stock_items(conn)
        @test length(out_of_stock) == 1
        @test out_of_stock[1].code == "C001"
        
        # テスト: 低在庫商品の検索
        low_stock = get_low_stock_items(conn, 50)
        @test length(low_stock) == 1
        @test low_stock[1].code == "C001"
        
        db_close(conn)
    end
    
    @testset "トランザクション" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト: トランザクションの開始・コミット
        @test_nowarn begin_transaction(conn)
        
        test_stock = Stock(
            1,
            "トランザクションテスト",
            "TRANS001",
            100,
            "個",
            1000.0,
            "テストカテゴリ",
            "A-1-1",
            now(),
            now()
        )
        
        insert_stock(conn, test_stock)
        @test_nowarn commit_transaction(conn)
        
        # コミット後にデータが存在することを確認
        stock = get_stock_by_id(conn, 1)
        @test stock !== nothing
        
        # テスト: トランザクションのロールバック
        @test_nowarn begin_transaction(conn)
        
        test_stock2 = Stock(
            2,
            "ロールバックテスト",
            "ROLLBACK001",
            50,
            "個",
            2000.0,
            "テストカテゴリ",
            "A-1-2",
            now(),
            now()
        )
        
        insert_stock(conn, test_stock2)
        @test_nowarn rollback_transaction(conn)
        
        # ロールバック後にデータが存在しないことを確認
        stock2 = get_stock_by_id(conn, 2)
        @test stock2 === nothing
        
        db_close(conn)
    end
end