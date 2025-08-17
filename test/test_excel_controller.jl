using Test
using HTTP
using JSON3
using XLSX
using DataFrames
using Dates

include("../src/web/controllers/ExcelController.jl")
include("../src/web/controllers/StockController.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")

@testset "ExcelController Tests" begin
    # テスト用DB初期化
    test_db_path = "data/test_inventory_excel.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end
    
    @testset "export_excel - Excelエクスポート" begin
        # テストデータを準備
        _ = StockController.create(Dict("product_code" => "EXP001","product_name" => "エクスポート商品1","category" => "テスト","quantity" => 100,"unit" => "個","price" => 1000.0,"location"=>"E-1"))
        _ = StockController.create(Dict("product_code" => "EXP002","product_name" => "エクスポート商品2","category" => "テスト","quantity" => 200,"unit" => "個","price" => 2000.0,"location"=>"E-2"))
        
        # コントローラーメソッドを呼び出し
        response = ExcelController.export_excel()
        
        # レスポンスの検証
        @test response.status == 200
        @test response.headers["Content-Type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        @test startswith(response.headers["Content-Disposition"], "attachment; filename=\"inventory_export_")
        
        # ファイルが正しく生成されたか確認
        @test !isempty(response.body)
    end
    
    @testset "import_excel - Excelインポート" begin
        # テスト用のExcelファイルを作成
        test_file_path = "test_import.xlsx"
        
        # インポート用のデータフレームを作成
        df = DataFrame(
            product_code = ["IMP001", "IMP002"],
            product_name = ["インポート商品1", "インポート商品2"],
            category = ["テスト", "テスト"],
            quantity = [50, 75],
            unit = ["個", "個"],
            price = [500, 750]
        )
        
        # Excelファイルに書き込み
        XLSX.writetable(test_file_path, "在庫データ" => df)
        
        # ファイルアップロードのシミュレーション
        file_content = read(test_file_path)
        
        # コントローラーメソッドを呼び出し（ファイルパスを渡す）
        response = ExcelController.import_excel(test_file_path)
        
        # レスポンスの検証
        @test response.status == 200
        data = JSON3.read(String(response.body))
        @test data[:success] == true
        @test data[:imported_count] == 2
        @test data[:message] == "Excelファイルのインポートが完了しました"
        
        # データベースに正しくインポートされたか確認
        # DBから確認
        conn = ConnectionPool.get_connection_from_pool()
        try
            stocks = SecureDuckDBConnection.secure_get_all_stocks(conn)
            codes = Set(s.code for s in stocks)
            @test "IMP001" in codes && "IMP002" in codes
        finally
            ConnectionPool.return_connection_to_pool(conn)
        end
        
        # テストファイルを削除
        rm(test_file_path, force=true)
    end
    
    @testset "エラーハンドリング" begin
        # 不正なファイルでのインポート
        response = ExcelController.import_excel("non_existent_file.xlsx")
        @test response.status == 400
        data = JSON3.read(String(response.body))
        @test haskey(data, :error)
    end
    
    # テスト後のクリーンアップ
    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
