using Test
using Dates

# 必要な関数をインポート
using .InventorySystem: Stock, add_quantity, reduce_quantity, filter_by_category, 
                       filter_out_of_stock, filter_low_stock, calculate_total_value, 
                       calculate_category_stats

@testset "Stock Model Tests" begin
    
    @testset "Stock構造体の作成" begin
        # テスト: 基本的なStock構造体が作成できること
        @test_nowarn Stock(
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
    end
    
    @testset "Stock構造体のバリデーション" begin
        # テスト: 必須フィールドの検証
        stock = Stock(
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
        
        # IDが正の整数であること
        @test stock.id > 0
        
        # 商品名が空でないこと
        @test !isempty(stock.name)
        
        # 商品コードが空でないこと
        @test !isempty(stock.code)
        
        # 数量が非負であること
        @test stock.quantity >= 0
        
        # 価格が非負であること
        @test stock.price >= 0.0
    end
    
    @testset "Stock構造体の日本語対応" begin
        # テスト: 日本語の商品名とカテゴリが正しく扱えること
        stock = Stock(
            1,
            "日本語商品名テスト",
            "JP001",
            50,
            "個",
            2000.0,
            "日本語カテゴリ",
            "倉庫A-棚1-位置1",
            now(),
            now()
        )
        
        @test stock.name == "日本語商品名テスト"
        @test stock.category == "日本語カテゴリ"
        @test stock.location == "倉庫A-棚1-位置1"
    end
    
    @testset "Stock操作関数" begin
        # テスト: 在庫を増やす関数
        stock = Stock(
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
        
        # 在庫追加のテスト
        new_stock = add_quantity(stock, 50)
        @test new_stock.quantity == 150
        @test new_stock.updated_at > stock.updated_at
        
        # 在庫減少のテスト
        reduced_stock = reduce_quantity(stock, 30)
        @test reduced_stock.quantity == 70
        @test reduced_stock.updated_at > stock.updated_at
        
        # 在庫不足の場合のエラーテスト
        @test_throws ArgumentError reduce_quantity(stock, 150)
    end
    
    @testset "Stock検索・フィルタリング" begin
        stocks = [
            Stock(1, "商品A", "A001", 100, "個", 1000.0, "カテゴリ1", "A-1-1", now(), now()),
            Stock(2, "商品B", "B001", 50, "個", 2000.0, "カテゴリ2", "A-1-2", now(), now()),
            Stock(3, "商品C", "C001", 0, "個", 1500.0, "カテゴリ1", "A-2-1", now(), now())
        ]
        
        # カテゴリによるフィルタリング
        category1_stocks = filter_by_category(stocks, "カテゴリ1")
        @test length(category1_stocks) == 2
        
        # 在庫切れ商品の検索
        out_of_stock = filter_out_of_stock(stocks)
        @test length(out_of_stock) == 1
        @test out_of_stock[1].code == "C001"
        
        # 低在庫商品の検索（閾値50未満）
        low_stock = filter_low_stock(stocks, 50)
        @test length(low_stock) == 1
        @test low_stock[1].code == "C001"
    end
    
    @testset "Stock統計情報" begin
        stocks = [
            Stock(1, "商品A", "A001", 100, "個", 1000.0, "カテゴリ1", "A-1-1", now(), now()),
            Stock(2, "商品B", "B001", 50, "個", 2000.0, "カテゴリ2", "A-1-2", now(), now()),
            Stock(3, "商品C", "C001", 75, "個", 1500.0, "カテゴリ1", "A-2-1", now(), now())
        ]
        
        # 総在庫価値の計算
        total_value = calculate_total_value(stocks)
        @test total_value == 312500.0  # (100*1000 + 50*2000 + 75*1500)
        
        # カテゴリ別統計
        category_stats = calculate_category_stats(stocks)
        @test haskey(category_stats, "カテゴリ1")
        @test haskey(category_stats, "カテゴリ2")
        @test category_stats["カテゴリ1"][:total_quantity] == 175
        @test category_stats["カテゴリ2"][:total_quantity] == 50
    end
end