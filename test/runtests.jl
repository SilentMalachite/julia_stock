using Test

# メインモジュールをインクルード
include("../src/InventorySystem.jl")
using .InventorySystem

# テストファイルを順次実行
@testset "InventorySystem Tests" begin
    @testset "Stock Model Tests" begin
        include("test_stock_model.jl")
    end
    
    @testset "DuckDB Connection Tests" begin
        include("test_duckdb_connection.jl")
    end
    
    @testset "Excel Handler Tests" begin
        include("test_excel_handler.jl")
    end
    
    @testset "Security Tests" begin
        include("test_security.jl")
    end
    
    @testset "Authentication Tests" begin
        include("test_authentication.jl")
    end
    
    @testset "Error Handling Tests" begin
        include("test_error_handling.jl")
    end
    
    @testset "Connection Management Tests" begin
        include("test_connection_management.jl")
    end
    
    @testset "Web API Tests" begin
        include("test_web_api.jl")
    end
    
    @testset "Controller Tests" begin
        include("test_stock_controller.jl")
        include("test_excel_controller.jl")
    end
    
    @testset "Routes Tests" begin
        include("test_routes.jl")
    end
    
    @testset "Integration Tests" begin
        include("test_integration.jl")
    end
    
    @testset "Backup Tests" begin
        include("test_backup.jl")
    end
    
    @testset "Modern GUI Tests" begin
        include("test_frontend_gui.jl")
    end
    
    @testset "Modern API Tests" begin
        include("test_modern_api.jl")
    end
end

println("全てのテストが完了しました。")