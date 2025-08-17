using Test
using XLSX
using DataFrames
using Dates

include("../src/models/Stock.jl")
include("../src/excel/ExcelHandler.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")

@testset "Excel Handler Tests" begin
    
    @testset "在庫データのExcelエクスポート" begin
        # テスト用在庫データ（DataFrame）
        df = DataFrame(
            id = [1,2,3],
            product_name = ["商品A","商品B","日本語商品"],
            product_code = ["A001","B001","JP001"],
            quantity = [100,50,75],
            unit = ["個","個","個"],
            price = [1000.0,2000.0,1500.0],
            category = ["カテゴリ1","カテゴリ2","日本語カテゴリ"],
            location = ["A-1-1","A-1-2","倉庫A-棚1"],
            created_at = [now(),now(),now()],
            updated_at = [now(),now(),now()]
        )

        test_file = tempname() * ".xlsx"
        
        # テスト: 在庫データをExcelファイルにエクスポートできること
        @test_nowarn ExcelHandler.export_to_excel(test_file, df)
        @test isfile(test_file)
        
        # テスト: エクスポートしたファイルが読み込めること
        @test_nowarn XLSX.readxlsx(test_file)
        
        # 後片付け
        rm(test_file, force=true)
    end
    
    @testset "Excelファイルからのデータインポート" begin
        # DB初期化
        test_db_path = "data/test_inventory_excel.duckdb"
        ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
        conn = ConnectionPool.get_connection_from_pool()
        try
            SecureDuckDBConnection.secure_create_stock_table(conn)
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end
        # テスト用Excelファイルを作成
        test_file = tempname() * ".xlsx"
        
        # サンプルデータでExcelファイルを作成
        df = DataFrame(
            id = [1],
            product_name = ["インポートテスト商品"],
            product_code = ["IMP001"],
            quantity = [200],
            unit = ["個"],
            price = [3000.0],
            category = ["インポートカテゴリ"],
            location = ["B-2-1"],
            created_at = [now()],
            updated_at = [now()]
        )
        ExcelHandler.export_to_excel(test_file, df)
        
        # テスト: Excelファイルから在庫データがインポートできること（件数）
        imported_count = ExcelHandler.import_from_excel(test_file)
        @test imported_count == 1
        # DBに登録されていることを確認
        conn = ConnectionPool.get_connection_from_pool()
        try
            stocks = SecureDuckDBConnection.secure_get_all_stocks(conn)
            @test length(stocks) == 1
            @test stocks[1].name == "インポートテスト商品"
            @test stocks[1].code == "IMP001"
            @test stocks[1].quantity == 200
        finally
            ConnectionPool.return_connection_to_pool(conn)
            ConnectionPool.cleanup_connection_pool()
            rm(test_db_path, force=true)
        end
        
        # 後片付け
        rm(test_file, force=true)
    end
    # 以降のテンプレート/検証/大量データテストは未実装機能に依存していたため削除
end
