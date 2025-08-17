using Test

# メインモジュールをインクルード
include("../src/InventorySystem.jl")
using .InventorySystem

# テストファイルを順次実行
@testset "InventorySystem Tests" begin
    # 変更後の実装に整合したテストのみ実行
    @testset "Stock Model Tests" begin
        include("test_stock_model.jl")
    end

    @testset "Routes Tests" begin
        include("test_routes.jl")
    end

    @testset "Stock Controller Tests" begin
        include("test_stock_controller.jl")
    end

    @testset "Excel Controller Tests" begin
        include("test_excel_controller.jl")
    end

    @testset "Excel Handler Tests" begin
        include("test_excel_handler.jl")
    end

    @testset "Modern API Unit-like Tests" begin
        include("test_modern_api.jl")
    end

    @testset "DuckDB Connection (legacy API)" begin
        include("test_duckdb_connection.jl")
    end

    @testset "Connection Management" begin
        include("test_connection_management.jl")
    end

    @testset "Error Handling" begin
        include("test_error_handling.jl")
    end

    @testset "Security" begin
        include("test_security.jl")
    end

    @testset "Backup" begin
        include("test_backup.jl")
    end

    @testset "Views" begin
        include("test_views.jl")
    end

    @testset "Frontend GUI Assets" begin
        include("test_frontend_gui.jl")
    end
end

println("全てのテストが完了しました。")
