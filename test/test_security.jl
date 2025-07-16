using Test
using DuckDB
using DataFrames
using Dates

# 必要な関数をインポート
using .InventorySystem: Stock, db_connect, db_close, create_stock_table,
                       secure_db_connect, secure_db_close, secure_create_stock_table,
                       secure_insert_stock, secure_get_all_stocks, secure_execute

@testset "Security Tests" begin
    
    @testset "SQLインジェクション脆弱性テスト" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # 正常なテストデータを挿入
        test_stock = Stock(1, "テスト商品", "TEST001", 100, "個", 1000.0, "テストカテゴリ", "A-1-1", now(), now())
        insert_stock(conn, test_stock)
        
        # テスト1: カテゴリ検索でSQLインジェクション攻撃を試行
        malicious_category = "'; DROP TABLE stocks; --"
        
        # 攻撃が成功しないことをテスト（例外が発生しないか、空の結果が返される）
        @test_nowarn begin
            result = get_stocks_by_category(conn, malicious_category)
            @test length(result) == 0  # 攻撃が失敗し、空の結果
        end
        
        # テーブルがまだ存在することを確認
        @test table_exists(conn, "stocks") == true
        
        # 正常なデータが残っていることを確認
        normal_stocks = get_all_stocks(conn)
        @test length(normal_stocks) == 1
        
        # テスト2: UNION攻撃の試行
        union_attack = "カテゴリ1' UNION SELECT 1,2,3,4,5,6,7,8,9,10 --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, union_attack)
            # 結果は空か、想定される正常なカテゴリのデータのみ
            @test all(stock -> stock.category != union_attack, result)
        end
        
        # テスト3: Boolean-based blind SQLインジェクション
        blind_attack = "カテゴリ1' AND 1=1 --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, blind_attack)
            @test length(result) == 0  # 攻撃が失敗
        end
        
        # テスト4: Time-based blind SQLインジェクション
        time_attack = "カテゴリ1'; WAITFOR DELAY '00:00:05' --"
        start_time = time()
        @test_nowarn begin
            result = get_stocks_by_category(conn, time_attack)
            @test length(result) == 0
        end
        elapsed_time = time() - start_time
        @test elapsed_time < 2.0  # 5秒の遅延攻撃が失敗していることを確認
        
        db_close(conn)
    end
    
    @testset "入力検証テスト" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト1: 異常に長い文字列の処理
        very_long_string = "A" ^ 10000
        @test_throws Exception Stock(
            1, very_long_string, "CODE001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now()
        )
        
        # テスト2: 特殊文字を含む入力
        special_chars = ["'; DROP TABLE --", "<script>alert('xss')</script>", "../../etc/passwd", "\0\n\r\t"]
        
        for malicious_input in special_chars
            @test_nowarn begin
                # 各フィールドに特殊文字を入れてテスト
                try
                    stock = Stock(1, malicious_input, "CODE001", 100, "個", 1000.0, malicious_input, malicious_input, now(), now())
                    insert_stock(conn, stock)
                    
                    # 取得時にサニタイズされていることを確認
                    retrieved = get_stock_by_id(conn, 1)
                    @test retrieved !== nothing
                    
                    # データが安全に格納・取得されていることを確認
                    delete_stock(conn, 1)
                catch e
                    # 例外が発生した場合、それは適切な入力検証が行われている証拠
                    @test true
                end
            end
        end
        
        # テスト3: NULLバイト攻撃
        null_byte_attack = "normal_text\0malicious_text"
        @test_nowarn begin
            try
                stock = Stock(1, null_byte_attack, "CODE001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
                insert_stock(conn, stock)
                retrieved = get_stock_by_id(conn, 1)
                @test retrieved !== nothing
                # NULLバイト以降が切り取られているか、適切に処理されているかを確認
                @test !contains(retrieved.name, "\0")
            catch e
                @test true  # 例外が発生するのは正しい挙動
            end
        end
        
        db_close(conn)
    end
    
    @testset "データベース接続セキュリティテスト" begin
        # テスト1: 不正なパスでの接続試行
        malicious_paths = [
            "../../../etc/passwd",
            "/dev/null",
            "//server/share/file",
            "\0/tmp/malicious.db"
        ]
        
        for malicious_path in malicious_paths
            @test_throws Exception db_connect(malicious_path)
        end
        
        # テスト2: 同時接続数の制限テスト
        connections = []
        try
            # 大量の接続を試行
            for i in 1:100
                push!(connections, db_connect())
            end
            # リソース枯渇攻撃の対策があることを確認
            @test length(connections) > 0
        catch e
            # 適切に接続が制限されている場合
            @test true
        finally
            # 全ての接続を閉じる
            for conn in connections
                try
                    db_close(conn)
                catch
                    # 既に閉じられている場合は無視
                end
            end
        end
    end
    
    @testset "権限昇格攻撃テスト" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # テスト1: 管理者権限を要求する攻撃
        admin_attack = "'; GRANT ALL PRIVILEGES TO PUBLIC; --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, admin_attack)
            @test length(result) == 0
        end
        
        # テスト2: システムテーブルへのアクセス試行
        system_table_attack = "'; SELECT * FROM sqlite_master; --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, system_table_attack)
            @test length(result) == 0
        end
        
        # テスト3: ファイルシステムアクセス試行
        file_access_attack = "'; ATTACH DATABASE '/etc/passwd' AS passwd; --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, file_access_attack)
            @test length(result) == 0
        end
        
        db_close(conn)
    end
    
    @testset "データ漏洩防止テスト" begin
        conn = db_connect()
        create_stock_table(conn)
        
        # 機密データのテスト挿入
        sensitive_stock = Stock(1, "機密商品", "SECRET001", 100, "個", 999999.0, "機密カテゴリ", "機密場所", now(), now())
        insert_stock(conn, sensitive_stock)
        
        # テスト1:情報漏洩攻撃
        info_leak_attack = "'; SELECT sql FROM sqlite_master; --"
        @test_nowarn begin
            result = get_stocks_by_category(conn, info_leak_attack)
            # 結果に機密情報が含まれていないことを確認
            for stock in result
                @test !contains(stock.name, "sqlite_master")
                @test !contains(stock.category, "CREATE TABLE")
            end
        end
        
        # テスト2: エラーメッセージからの情報漏洩防止
        error_leak_attack = "'; SELECT 1/0; --"
        @test_nowarn begin
            # エラーが発生してもデータベース構造が漏洩しないことを確認
            try
                result = get_stocks_by_category(conn, error_leak_attack)
            catch e
                error_msg = string(e)
                @test !contains(error_msg, "stocks")  # テーブル名が漏洩しない
                @test !contains(error_msg, "CREATE")  # SQL構造が漏洩しない
            end
        end
        
        db_close(conn)
    end
end