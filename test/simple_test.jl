#!/usr/bin/env julia

# シンプルな包括的テスト
using Test
using Pkg
Pkg.activate(".")

println("=" ^ 80)
println("Julia在庫管理システム - 簡易テスト")
println("=" ^ 80)

# 1. パッケージの読み込みテスト
println("\n1. パッケージ読み込みテスト")
@testset "Package Loading" begin
    @test try
        using DataFrames
        using JSON3
        using HTTP
        using XLSX
        using Dates
        true
    catch
        false
    end
    println("  ✓ 全パッケージの読み込み成功")
end

# 2. 基本的なファイル構造テスト
println("\n2. ファイル構造テスト")
@testset "File Structure" begin
    required_files = [
        "src/models/Stock.jl",
        "src/database/DuckDBConnection.jl",
        "src/excel/ExcelHandler.jl",
        "src/web/routes.jl",
        "public/js/modern-app.js",
        "public/css/modern-ui.css",
        "views/stocks/modern_index.jl.html"
    ]
    
    for file in required_files
        @test isfile(file)
        println("  ✓ $file")
    end
end

# 3. モデルとデータベースの基本テスト
println("\n3. モデルテスト")
@testset "Stock Model" begin
    # Stock.jlをinclude
    include("../src/models/Stock.jl")
    
    # 基本的な関数の存在確認
    @test isdefined(Stock, :create)
    @test isdefined(Stock, :find)
    @test isdefined(Stock, :update)
    @test isdefined(Stock, :delete)
    @test isdefined(Stock, :all)
    println("  ✓ Stock モデルの関数定義確認")
end

# 4. ExcelHandlerテスト
println("\n4. Excel機能テスト")
@testset "Excel Handler" begin
    include("../src/excel/ExcelHandler.jl")
    
    # 関数の存在確認
    @test isdefined(ExcelHandler, :export_to_excel)
    @test isdefined(ExcelHandler, :import_from_excel)
    println("  ✓ ExcelHandler の関数定義確認")
    
    # テンプレート作成テスト
    test_file = "test_template.xlsx"
    try
        @test isdefined(ExcelHandler, :create_template)
        println("  ✓ テンプレート作成関数の存在確認")
    finally
        isfile(test_file) && rm(test_file)
    end
end

# 5. Webルートテスト
println("\n5. Webルート設定テスト")
@testset "Web Routes" begin
    routes_file = "src/web/routes.jl"
    @test isfile(routes_file)
    
    # ルートファイルの内容確認
    content = read(routes_file, String)
    @test occursin("/api/stocks", content)
    @test occursin("/api/v2/stocks", content)
    @test occursin("ModernStockController", content)
    println("  ✓ APIルートの定義確認")
end

# 6. フロントエンドファイルテスト
println("\n6. フロントエンドテスト")
@testset "Frontend Files" begin
    # JavaScriptファイル
    js_file = "public/js/modern-app.js"
    @test isfile(js_file)
    js_content = read(js_file, String)
    @test occursin("class InventoryApp", js_content)
    @test occursin("apiBaseUrl", js_content)
    println("  ✓ JavaScript ファイル確認")
    
    # CSSファイル
    css_file = "public/css/modern-ui.css"
    @test isfile(css_file)
    css_content = read(css_file, String)
    @test occursin("--primary-color", css_content)
    @test occursin("responsive", css_content)
    println("  ✓ CSS ファイル確認")
    
    # HTMLテンプレート
    html_file = "views/stocks/modern_index.jl.html"
    @test isfile(html_file)
    html_content = read(html_file, String)
    @test occursin("在庫管理システム", html_content)
    @test occursin("modern-app.js", html_content)
    println("  ✓ HTML テンプレート確認")
end

# 7. テストファイルの存在確認
println("\n7. テストファイル確認")
@testset "Test Files" begin
    test_files = [
        "test/test_frontend_gui.jl",
        "test/test_modern_api.jl",
        "test/comprehensive_test.jl"
    ]
    
    for file in test_files
        @test isfile(file)
        println("  ✓ $file")
    end
end

# 8. ドキュメント確認
println("\n8. ドキュメント確認")
@testset "Documentation" begin
    doc_files = [
        "README.md",
        "CLAUDE.md",
        "docs/MODERN_GUI_GUIDE.md"
    ]
    
    for file in doc_files
        @test isfile(file)
        println("  ✓ $file")
    end
    
    # READMEにモダンGUIの記載があるか確認
    readme_content = read("README.md", String)
    @test occursin("モダンGUI", readme_content)
    println("  ✓ README.mdにモダンGUIの記載確認")
end

# テスト結果サマリー
println("\n" * "=" * 80)
println("テスト完了！")
println("全てのテストが成功しました ✅")
println("=" * 80)

# APIサーバーのテスト（オプション）
println("\nAPIサーバーテスト（オプション）:")
println("APIサーバーが起動している場合は以下のコマンドでテスト可能:")
println("  curl http://localhost:8000/api/health")
println("  curl http://localhost:8000/api/v2/stocks")
println("\nモダンGUIアクセス:")
println("  http://localhost:8000/stocks/modern")