using Test
using HTTP
using JSON3
using XLSX
using DataFrames
using Dates
using Genie

include("../src/web/controllers/ExcelController.jl")
include("../src/models/Stock.jl")
include("../src/database/DuckDBConnection.jl")
include("../src/excel/ExcelHandler.jl")

@testset "ExcelController Tests" begin
    # テスト用のデータベース接続を設定
    test_db_path = "data/test_inventory.duckdb"
    DuckDBConnection.initialize_database(test_db_path)
    
    @testset "export_excel - Excelエクスポート" begin
        # テストデータを準備
        Stock.create(Dict(
            "product_code" => "EXP001",
            "product_name" => "エクスポート商品1",
            "category" => "テスト",
            "quantity" => 100,
            "unit" => "個",
            "price" => 1000
        ))
        
        Stock.create(Dict(
            "product_code" => "EXP002",
            "product_name" => "エクスポート商品2",
            "category" => "テスト",
            "quantity" => 200,
            "unit" => "個",
            "price" => 2000
        ))
        
        # コントローラーメソッドを呼び出し
        response = ExcelController.export_excel()
        
        # レスポンスの検証
        @test response.status == 200
        @test response.headers["Content-Type"] == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        @test response.headers["Content-Disposition"] == "attachment; filename=\"inventory_export_$(Dates.format(now(), \"yyyymmdd_HHMMSS\")).xlsx\""
        
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
        imported_stock1 = Stock.find_by("product_code", "IMP001")
        @test imported_stock1[:product_name] == "インポート商品1"
        @test imported_stock1[:quantity] == 50
        
        imported_stock2 = Stock.find_by("product_code", "IMP002")
        @test imported_stock2[:product_name] == "インポート商品2"
        @test imported_stock2[:quantity] == 75
        
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
    rm(test_db_path, force=true)
end