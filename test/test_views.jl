using Test
using Genie
using Genie.Renderer.Html

include("../src/web/views/ViewHelpers.jl")

@testset "View Tests" begin
    @testset "Layout Template" begin
        # レイアウトファイルが存在するか確認
        layout_path = "src/web/views/layouts/app.jl.html"
        @test isfile(layout_path)
        
        # レイアウトが正しくレンダリングされるか確認
        content = html(:test, :content => "Test Content")
        @test occursin("<!DOCTYPE html>", content)
        @test occursin("Test Content", content)
    end
    
    @testset "Stock Views" begin
        # 在庫一覧ビュー
        index_path = "src/web/views/stocks/index.jl.html"
        @test isfile(index_path)
        
        # 在庫詳細ビュー
        show_path = "src/web/views/stocks/show.jl.html"
        @test isfile(show_path)
        
        # 在庫作成フォーム
        new_path = "src/web/views/stocks/new.jl.html"
        @test isfile(new_path)
        
        # 在庫編集フォーム
        edit_path = "src/web/views/stocks/edit.jl.html"
        @test isfile(edit_path)
    end
    
    @testset "ViewHelpers" begin
        # フォームヘルパーのテスト
        @test isdefined(ViewHelpers, :form_input)
        @test isdefined(ViewHelpers, :form_select)
        @test isdefined(ViewHelpers, :form_button)
        
        # URLヘルパーのテスト
        @test isdefined(ViewHelpers, :stock_path)
        @test isdefined(ViewHelpers, :stocks_path)
        @test isdefined(ViewHelpers, :new_stock_path)
        @test isdefined(ViewHelpers, :edit_stock_path)
        
        # フォーマットヘルパーのテスト
        @test isdefined(ViewHelpers, :format_currency)
        @test isdefined(ViewHelpers, :format_quantity)
        @test isdefined(ViewHelpers, :format_datetime)
    end
    
    @testset "Static Assets" begin
        # CSSファイルの存在確認
        @test isfile("public/css/app.css")
        
        # JavaScriptファイルの存在確認
        @test isfile("public/js/app.js")
        
        # 画像ディレクトリの存在確認
        @test isdir("public/images")
    end
end