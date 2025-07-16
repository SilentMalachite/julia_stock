using Test
using XLSX
using DataFrames
using Dates

# 必要な関数をインポート
using .InventorySystem: Stock, create_empty_excel, export_stocks_to_excel, 
                       import_stocks_from_excel, create_stock_template, 
                       get_excel_headers, validate_excel_format

@testset "Excel Handler Tests" begin
    
    @testset "Excelファイル作成・保存" begin
        # テスト: 空のExcelファイルが作成できること
        test_file = tempname() * ".xlsx"
        @test_nowarn create_empty_excel(test_file)
        @test isfile(test_file)
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "在庫データのExcelエクスポート" begin
        # テスト用在庫データ
        stocks = [
            Stock(1, "商品A", "A001", 100, "個", 1000.0, "カテゴリ1", "A-1-1", now(), now()),
            Stock(2, "商品B", "B001", 50, "個", 2000.0, "カテゴリ2", "A-1-2", now(), now()),
            Stock(3, "日本語商品", "JP001", 75, "個", 1500.0, "日本語カテゴリ", "倉庫A-棚1", now(), now())
        ]
        
        test_file = tempname() * ".xlsx"
        
        # テスト: 在庫データをExcelファイルにエクスポートできること
        @test_nowarn export_stocks_to_excel(stocks, test_file)
        @test isfile(test_file)
        
        # テスト: エクスポートしたファイルが読み込めること
        @test_nowarn XLSX.readxlsx(test_file)
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "Excelファイルからのデータインポート" begin
        # テスト用Excelファイルを作成
        test_file = tempname() * ".xlsx"
        
        # サンプルデータでExcelファイルを作成
        stocks = [
            Stock(1, "インポートテスト商品", "IMP001", 200, "個", 3000.0, "インポートカテゴリ", "B-2-1", now(), now())
        ]
        export_stocks_to_excel(stocks, test_file)
        
        # テスト: Excelファイルから在庫データがインポートできること
        imported_stocks = import_stocks_from_excel(test_file)
        @test length(imported_stocks) == 1
        @test imported_stocks[1].name == "インポートテスト商品"
        @test imported_stocks[1].code == "IMP001"
        @test imported_stocks[1].quantity == 200
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "日本語データのExcel処理" begin
        # 日本語を含む在庫データ
        japanese_stocks = [
            Stock(1, "日本語商品名テスト", "JP001", 100, "個", 1000.0, "日本語カテゴリ", "倉庫A-棚1-位置1", now(), now()),
            Stock(2, "ひらがなカタカナ商品", "HIRA001", 50, "箱", 2000.0, "テストカテゴリ", "倉庫B-棚2-位置2", now(), now())
        ]
        
        test_file = tempname() * ".xlsx"
        
        # テスト: 日本語データがExcelに正しく保存・読み込みできること
        @test_nowarn export_stocks_to_excel(japanese_stocks, test_file)
        
        imported_stocks = import_stocks_from_excel(test_file)
        @test length(imported_stocks) == 2
        @test imported_stocks[1].name == "日本語商品名テスト"
        @test imported_stocks[1].location == "倉庫A-棚1-位置1"
        @test imported_stocks[2].name == "ひらがなカタカナ商品"
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "Excelテンプレート機能" begin
        test_template = tempname() * ".xlsx"
        
        # テスト: 在庫入力用テンプレートが作成できること
        @test_nowarn create_stock_template(test_template)
        @test isfile(test_template)
        
        # テスト: テンプレートに必要なヘッダーが含まれていること
        headers = get_excel_headers(test_template)
        expected_headers = ["ID", "商品名", "商品コード", "数量", "単位", "価格", "カテゴリ", "保管場所", "作成日時", "更新日時"]
        @test length(headers) == length(expected_headers)
        for header in expected_headers
            @test header in headers
        end
        
        # 後片付け
        rm(test_template, force=true)
    end
    
    @testset "Excel検証機能" begin
        # 正しいフォーマットのテストファイル
        valid_file = tempname() * ".xlsx"
        stocks = [Stock(1, "検証テスト", "VAL001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())]
        export_stocks_to_excel(stocks, valid_file)
        
        # テスト: 正しいExcelファイルが検証を通ること
        @test validate_excel_format(valid_file) == true
        
        # 不正なフォーマットのテストファイル（空ファイル）
        invalid_file = tempname() * ".xlsx"
        create_empty_excel(invalid_file)
        
        # テスト: 不正なフォーマットが検証でエラーになること
        @test validate_excel_format(invalid_file) == false
        
        # 後片付け
        rm(valid_file, force=true)
        rm(invalid_file, force=true)
    end
    
    @testset "大量データのExcel処理" begin
        # 大量のテストデータ生成（1000件）
        large_stocks = Stock[]
        for i in 1:1000
            push!(large_stocks, Stock(
                i,
                "商品$i",
                "CODE$(lpad(i, 4, '0'))",
                rand(1:100),
                "個",
                rand(100.0:10000.0),
                "カテゴリ$(rand(1:5))",
                "A-$(rand(1:10))-$(rand(1:10))",
                now(),
                now()
            ))
        end
        
        test_file = tempname() * ".xlsx"
        
        # テスト: 大量データのエクスポートが正常に行えること
        @test_nowarn export_stocks_to_excel(large_stocks, test_file)
        @test isfile(test_file)
        
        # テスト: 大量データのインポートが正常に行えること
        imported_stocks = import_stocks_from_excel(test_file)
        @test length(imported_stocks) == 1000
        @test imported_stocks[1].name == "商品1"
        @test imported_stocks[1000].name == "商品1000"
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "エラーハンドリング" begin
        # テスト: 存在しないファイルのインポートでエラーが発生すること
        @test_throws Exception import_stocks_from_excel("nonexistent.xlsx")
        
        # テスト: 読み取り専用ディレクトリへの書き込みでエラーが発生すること
        # Note: この部分は環境によって異なる可能性があるため、スキップする場合もある
        
        # テスト: 空のデータでのエクスポートが正常に処理されること
        empty_stocks = Stock[]
        test_file = tempname() * ".xlsx"
        @test_nowarn export_stocks_to_excel(empty_stocks, test_file)
        
        imported_empty = import_stocks_from_excel(test_file)
        @test length(imported_empty) == 0
        
        # 後片付け
        rm(test_file, force=true)
    end
end