using Test
using JSON3
using Dates

include("../src/web/controllers/StockController.jl")
include("../src/web/controllers/ExcelController.jl")
include("../src/database/ConnectionPool.jl")
include("../src/database/SecureDuckDBConnection.jl")

@testset "Web API Controller-like Tests" begin
    # DB初期化
    test_db_path = "data/test_inventory_webapi.duckdb"
    ConnectionPool.init_connection_pool(; max_connections=2, min_connections=1, database_path=test_db_path)
    conn = ConnectionPool.get_connection_from_pool()
    try
        SecureDuckDBConnection.secure_create_stock_table(conn)
    finally
        ConnectionPool.return_connection_to_pool(conn)
    end

    @testset "在庫のCRUD" begin
        # 作成
        create_resp = StockController.create(Dict("product_code"=>"NEW001","product_name"=>"新規商品","category"=>"新規","quantity"=>50,"unit"=>"個","price"=>2000.0,"location"=>"B-2-2"))
        @test create_resp.status == 201
        created = JSON3.read(String(create_resp.body))
        id = created[:id]

        # 一覧
        index_resp = StockController.index(); @test index_resp.status == 200

        # 取得
        show_resp = StockController.show(id); @test show_resp.status == 200

        # 更新
        upd_resp = StockController.update(id, Dict("product_name"=>"更新後","quantity"=>60)); @test upd_resp.status == 200

        # 削除
        del_resp = StockController.destroy(id); @test del_resp.status == 200
        show_after = StockController.show(id); @test show_after.status == 404
    end

    @testset "Excelエクスポート/インポート" begin
        # 事前に1件作成
        _ = StockController.create(Dict("product_code"=>"EX001","product_name"=>"エクスポート","category"=>"テスト","quantity"=>10,"unit"=>"個","price"=>1000.0,"location"=>"L-1"))
        # エクスポート
        exp = ExcelController.export_excel(); @test exp.status == 200
        @test occursin("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", exp.headers["Content-Type"])
        # インポート（簡易）
        using XLSX, DataFrames
        f = tempname()*".xlsx"
        df = DataFrame(product_code=["IMPX01"], product_name=["インポートX"], category=["テスト"], quantity=[5], unit=["個"], price=[500.0], location=["LX-1"])
        XLSX.writetable(f, "在庫データ"=>df)
        imp = ExcelController.import_excel(f); @test imp.status == 200
        rm(f, force=true)
    end

    ConnectionPool.cleanup_connection_pool()
    rm(test_db_path, force=true)
end
    
    # 以降のHTTPサーバーベースのテストはコントローラ直呼び出しに置き換え済み
    
    @testset "在庫追加API" begin
        start_api_server(8004)
        
        try
            # テスト: POST /api/stocks で新しい在庫が追加できること
            new_stock_data = Dict(
                "name" => "新規商品",
                "code" => "NEW001",
                "quantity" => 50,
                "unit" => "個",
                "price" => 2000.0,
                "category" => "新規カテゴリ",
                "location" => "B-2-2"
            )
            
            response = HTTP.post(
                "http://localhost:8004/api/stocks",
                headers=["Content-Type" => "application/json"],
                body=JSON3.write(new_stock_data)
            )
            
            @test response.status == 201
            
            data = JSON3.read(response.body)
            @test haskey(data, :stock)
            @test data.stock.name == "新規商品"
            @test data.stock.code == "NEW001"
            
            # テスト: 不正なデータで400エラーが返されること
            invalid_data = Dict("name" => "")  # 必須フィールドが不足
            
            response_400 = HTTP.post(
                "http://localhost:8004/api/stocks",
                headers=["Content-Type" => "application/json"],
                body=JSON3.write(invalid_data),
                status_exception=false
            )
            
            @test response_400.status == 400
            
        finally
            stop_api_server(8004)
        end
    end
    
    @testset "在庫更新API" begin
        start_api_server(8005)
        
        try
            # テスト用データを挿入
            test_stock = Stock(1, "更新テスト商品", "UPD001", 100, "個", 1000.0, "テストカテゴリ", "A-1-1", now(), now())
            add_test_stock(test_stock)
            
            # テスト: PUT /api/stocks/:id で在庫が更新できること
            update_data = Dict(
                "name" => "更新された商品",
                "quantity" => 150,
                "price" => 1500.0
            )
            
            response = HTTP.put(
                "http://localhost:8005/api/stocks/1",
                headers=["Content-Type" => "application/json"],
                body=JSON3.write(update_data)
            )
            
            @test response.status == 200
            
            data = JSON3.read(response.body)
            @test data.stock.name == "更新された商品"
            @test data.stock.quantity == 150
            @test data.stock.price == 1500.0
            
            # テスト: 存在しないIDで404が返されること
            response_404 = HTTP.put(
                "http://localhost:8005/api/stocks/999",
                headers=["Content-Type" => "application/json"],
                body=JSON3.write(update_data),
                status_exception=false
            )
            
            @test response_404.status == 404
            
        finally
            stop_api_server(8005)
        end
    end
    
    @testset "在庫削除API" begin
        start_api_server(8006)
        
        try
            # テスト用データを挿入
            test_stock = Stock(1, "削除テスト商品", "DEL001", 100, "個", 1000.0, "テストカテゴリ", "A-1-1", now(), now())
            add_test_stock(test_stock)
            
            # テスト: DELETE /api/stocks/:id で在庫が削除できること
            response = HTTP.delete("http://localhost:8006/api/stocks/1")
            @test response.status == 204
            
            # 削除確認
            response_get = HTTP.get("http://localhost:8006/api/stocks/1", status_exception=false)
            @test response_get.status == 404
            
            # テスト: 存在しないIDで404が返されること
            response_404 = HTTP.delete("http://localhost:8006/api/stocks/999", status_exception=false)
            @test response_404.status == 404
            
        finally
            stop_api_server(8006)
        end
    end
    
    @testset "Excel連携API" begin
        start_api_server(8007)
        
        try
            # テスト: POST /api/excel/import でExcelファイルがインポートできること
            # テスト用Excelファイルを作成
            test_stocks = [
                Stock(1, "インポート商品", "IMP001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
            ]
            test_file = tempname() * ".xlsx"
            export_stocks_to_excel(test_stocks, test_file)
            
            # ファイルアップロード
            response = HTTP.post(
                "http://localhost:8007/api/excel/import",
                body=HTTP.Form(["file" => HTTP.UploadFile(test_file, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")])
            )
            
            @test response.status == 200
            
            data = JSON3.read(response.body)
            @test haskey(data, :imported_count)
            @test data.imported_count == 1
            
            # テスト: GET /api/excel/export で在庫データがExcelでエクスポートできること
            response_export = HTTP.get("http://localhost:8007/api/excel/export")
            @test response_export.status == 200
            @test HTTP.header(response_export, "Content-Type") == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            
            # 後片付け
            rm(test_file, force=true)
            
        finally
            stop_api_server(8007)
        end
    end
    
    @testset "検索・フィルタリングAPI" begin
        start_api_server(8008)
        
        try
            # テスト用データを挿入
            test_stocks = [
                Stock(1, "商品A", "A001", 100, "個", 1000.0, "カテゴリ1", "A-1-1", now(), now()),
                Stock(2, "商品B", "B001", 0, "個", 2000.0, "カテゴリ2", "A-1-2", now(), now()),
                Stock(3, "商品C", "C001", 10, "個", 1500.0, "カテゴリ1", "A-2-1", now(), now())
            ]
            
            for stock in test_stocks
                add_test_stock(stock)
            end
            
            # テスト: GET /api/stocks?category=カテゴリ1 でカテゴリ検索ができること
            response = HTTP.get("http://localhost:8008/api/stocks?category=カテゴリ1")
            @test response.status == 200
            
            data = JSON3.read(response.body)
            @test length(data.stocks) == 2
            
            # テスト: GET /api/stocks/out-of-stock で在庫切れ商品が取得できること
            response_oos = HTTP.get("http://localhost:8008/api/stocks/out-of-stock")
            @test response_oos.status == 200
            
            data_oos = JSON3.read(response_oos.body)
            @test length(data_oos.stocks) == 1
            @test data_oos.stocks[1].code == "B001"
            
            # テスト: GET /api/stocks/low-stock?threshold=50 で低在庫商品が取得できること
            response_low = HTTP.get("http://localhost:8008/api/stocks/low-stock?threshold=50")
            @test response_low.status == 200
            
            data_low = JSON3.read(response_low.body)
            @test length(data_low.stocks) == 2  # quantity 0 と 10 の商品
            
        finally
            stop_api_server(8008)
        end
    end
    
    @testset "エラーハンドリング" begin
        start_api_server(8009)
        
        try
            # テスト: 不正なJSONで400エラーが返されること
            response_bad_json = HTTP.post(
                "http://localhost:8009/api/stocks",
                headers=["Content-Type" => "application/json"],
                body="invalid json",
                status_exception=false
            )
            
            @test response_bad_json.status == 400
            
            # テスト: 存在しないエンドポイントで404が返されること
            response_404 = HTTP.get("http://localhost:8009/api/nonexistent", status_exception=false)
            @test response_404.status == 404
            
            # テスト: POSTメソッドが許可されていないエンドポイントで405が返されること
            response_405 = HTTP.post("http://localhost:8009/api/stocks/1", status_exception=false)
            @test response_405.status == 405
            
        finally
            stop_api_server(8009)
        end
    end
    
    @testset "CORS設定" begin
        start_api_server(8010)
        
        try
            # テスト: CORS ヘッダーが正しく設定されていること
            response = HTTP.get("http://localhost:8010/api/stocks")
            @test response.status == 200
            
            # CORS ヘッダーの検証
            @test HTTP.header(response, "Access-Control-Allow-Origin") == "*"
            @test "GET" in split(HTTP.header(response, "Access-Control-Allow-Methods"), ", ")
            @test "POST" in split(HTTP.header(response, "Access-Control-Allow-Methods"), ", ")
            
        finally
            stop_api_server(8010)
        end
    end

