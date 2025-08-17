using Test

@testset "Frontend GUI Assets" begin
    # 主要なビューとアセットの存在確認（HTTP不要）
    @test isfile("views/stocks/modern_index.jl.html")
    @test isfile("public/css/modern-ui.css")
    @test isfile("public/js/modern-app.js")
    @test isfile("src/web/views/layouts/app.jl.html")
end

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
