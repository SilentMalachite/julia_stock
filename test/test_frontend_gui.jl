using Test
using HTTP
using JSON3
using Genie
using Genie.Renderer
using Genie.Renderer.Html

# フロントエンドGUIのテストスイート
@testset "Frontend GUI Tests" begin
    
    @testset "ホームページレンダリング" begin
        # ホームページが正しくレンダリングされることを確認
        response = HTTP.get("http://localhost:8000/")
        @test response.status == 200
        @test occursin("在庫管理システム", String(response.body))
        @test occursin("text/html", response.headers["Content-Type"])
    end
    
    @testset "在庫一覧ページ" begin
        # 在庫一覧ページのレンダリングテスト
        response = HTTP.get("http://localhost:8000/stocks")
        @test response.status == 200
        
        body = String(response.body)
        # 必要な要素が含まれているか確認
        @test occursin("在庫一覧", body)
        @test occursin("商品コード", body)
        @test occursin("商品名", body)
        @test occursin("在庫数", body)
        @test occursin("検索", body)
        @test occursin("新規登録", body)
    end
    
    @testset "レスポンシブデザイン" begin
        # モバイル、タブレット、デスクトップ対応の確認
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        # Bootstrap のレスポンシブクラスが使用されているか
        @test occursin("col-md-", body)
        @test occursin("table-responsive", body)
        @test occursin("viewport", body)
    end
    
    @testset "インタラクティブ要素" begin
        # JavaScriptによるインタラクティブ機能のテスト
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        # 必要なJavaScriptライブラリが読み込まれているか
        @test occursin("app.js", body)
        @test occursin("bootstrap", body)
        
        # データテーブル機能
        @test occursin("data-table", body) || occursin("table", body)
        
        # フォームバリデーション
        @test occursin("form-validation", body) || occursin("required", body)
    end
    
    @testset "モーダルダイアログ" begin
        # 追加・編集用モーダルのテスト
        response = HTTP.get("http://localhost:8000/stocks/new")
        body = String(response.body)
        
        # フォーム要素の確認
        @test occursin("<form", body)
        @test occursin("product_code", body)
        @test occursin("product_name", body)
        @test occursin("quantity", body)
        @test occursin("price", body)
    end
    
    @testset "検索・フィルター機能" begin
        # 検索フォームのテスト
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        @test occursin("search", body)
        @test occursin("category", body)
        @test occursin("filter", body) || occursin("検索", body)
    end
    
    @testset "Excel連携UI" begin
        # Excelインポート/エクスポートUIのテスト
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        @test occursin("import", body) || occursin("インポート", body)
        @test occursin("export", body) || occursin("エクスポート", body)
    end
    
    @testset "リアルタイム更新" begin
        # WebSocketまたはAJAXによるリアルタイム更新機能
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        # Ajax関連のスクリプトが含まれているか
        @test occursin("fetch", body) || occursin("ajax", body) || occursin("axios", body)
    end
    
    @testset "アクセシビリティ" begin
        # アクセシビリティ要件のテスト
        response = HTTP.get("http://localhost:8000/stocks")
        body = String(response.body)
        
        # ARIA属性
        @test occursin("aria-", body) || occursin("role=", body)
        
        # フォームラベル
        @test occursin("<label", body)
        
        # 代替テキスト
        @test !occursin("<img", body) || occursin("alt=", body)
    end
    
    @testset "エラーハンドリングUI" begin
        # エラー表示のテスト
        # 存在しないリソースへのアクセス
        response = HTTP.get("http://localhost:8000/stocks/999999", status_exception=false)
        
        if response.status == 404
            body = String(response.body)
            @test occursin("見つかりません", body) || occursin("not found", body)
        end
    end
end

# JavaScript単体テストのためのテストファイル生成
@testset "Generate JavaScript Test Files" begin
    js_test_content = """
    // Jest テスト設定
    describe('Inventory Management GUI', () => {
        describe('Stock List View', () => {
            test('should render stock table', () => {
                const table = document.querySelector('.stock-table');
                expect(table).toBeTruthy();
            });
            
            test('should have search functionality', () => {
                const searchInput = document.querySelector('#search-input');
                expect(searchInput).toBeTruthy();
            });
        });
        
        describe('Stock Form Validation', () => {
            test('should validate required fields', () => {
                const form = document.querySelector('#stock-form');
                const productCode = document.querySelector('#product_code');
                productCode.value = '';
                
                const isValid = form.checkValidity();
                expect(isValid).toBeFalsy();
            });
        });
        
        describe('Real-time Updates', () => {
            test('should update stock list without page reload', async () => {
                const updateButton = document.querySelector('.update-stock');
                updateButton.click();
                
                // 非同期更新を待つ
                await new Promise(resolve => setTimeout(resolve, 1000));
                
                const updatedData = document.querySelector('.stock-quantity');
                expect(updatedData.textContent).not.toBe('0');
            });
        });
    });
    """
    
    # JavaScriptテストファイルを作成
    mkpath("test/javascript")
    open("test/javascript/gui.test.js", "w") do f
        write(f, js_test_content)
    end
    
    @test isfile("test/javascript/gui.test.js")
end