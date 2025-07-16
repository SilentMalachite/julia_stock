using Test
using Genie
using Genie.Router
using HTTP

include("../src/web/routes.jl")

@testset "Routes Tests" begin
    @testset "ルート定義の確認" begin
        # ルートが正しく定義されているか確認
        routes = Router.routes()
        
        # API在庫ルート
        @test any(r -> r.path == "/api/stocks" && r.method == "GET", routes)
        @test any(r -> occursin(r"/api/stocks/\d+", r.path) && r.method == "GET", routes)
        @test any(r -> r.path == "/api/stocks" && r.method == "POST", routes)
        @test any(r -> occursin(r"/api/stocks/\d+", r.path) && r.method == "PUT", routes)
        @test any(r -> occursin(r"/api/stocks/\d+", r.path) && r.method == "DELETE", routes)
        
        # Excel連携ルート
        @test any(r -> r.path == "/api/excel/import" && r.method == "POST", routes)
        @test any(r -> r.path == "/api/excel/export" && r.method == "GET", routes)
    end
    
    @testset "ルートハンドラーの存在確認" begin
        # StockControllerのメソッドが呼び出せるか確認
        @test isdefined(StockController, :index)
        @test isdefined(StockController, :show)
        @test isdefined(StockController, :create)
        @test isdefined(StockController, :update)
        @test isdefined(StockController, :destroy)
        
        # ExcelControllerのメソッドが呼び出せるか確認
        @test isdefined(ExcelController, :import_excel)
        @test isdefined(ExcelController, :export_excel)
    end
end