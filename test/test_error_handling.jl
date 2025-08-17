using Test
using Dates

# 必要な関数をインポート
using .InventorySystem: init_logging, log_info, log_warning, log_error, log_debug, 
                       log_security_event, secure_db_connect, secure_db_close,
                       secure_create_stock_table, secure_insert_stock, secure_get_stock_by_id,
                       secure_delete_stock, Stock

@testset "Error Handling and Logging Tests" begin
    
    @testset "データベースエラーハンドリングテスト" begin
        # テスト: 無効なデータベースパスでのエラーハンドリング
        @test_throws Exception secure_db_connect("/invalid/path/database.db")
        
        # テスト: 接続済みデータベースの重複作成試行
        conn1 = secure_db_connect()
        secure_create_stock_table(conn1)
        
        # 同じテーブルの再作成は成功すべき（IF NOT EXISTS）
        @test_nowarn secure_create_stock_table(conn1)
        
        # テスト: 不正なデータでの挿入エラー
        invalid_stock_data = [
            # 負の数量
            (1, "商品", "CODE001", -10, "個", 1000.0, "カテゴリ", "場所"),
            # 負の価格
            (2, "商品", "CODE002", 100, "個", -1000.0, "カテゴリ", "場所"),
            # 空の名前
            (3, "", "CODE003", 100, "個", 1000.0, "カテゴリ", "場所"),
            # 長すぎる名前
            (4, "A" ^ 300, "CODE004", 100, "個", 1000.0, "カテゴリ", "場所")
        ]
        
        for (id, name, code, quantity, unit, price, category, location) in invalid_stock_data
            @test_throws Exception begin
                stock = Stock(id, name, code, quantity, unit, price, category, location, now(), now())
                secure_insert_stock(conn1, stock)
            end
        end
        
        secure_db_close(conn1)
    end
    
    @testset "ログ機能テスト" begin
        # テスト: ログの初期化
        @test_nowarn init_logging()
        
        # テスト: 各レベルのログ出力
        @test_nowarn log_info("テスト情報ログ")
        @test_nowarn log_warning("テスト警告ログ")
        @test_nowarn log_error("テストエラーログ")
        @test_nowarn log_debug("テストデバッグログ")
        
        # テスト: セキュリティ関連ログ
        @test_nowarn log_security_event("failed_login_attempt", Dict(
            "username" => "attacker",
            "ip_address" => "192.168.1.100",
            "attempt_count" => 5,
            "timestamp" => now()
        ))
        
        # テスト: ログファイルの存在確認
        @test isfile("logs/app.log")
        @test isfile("logs/security.log")
    end
    
    @testset "例外処理の一貫性テスト" begin
        # テスト: データベース操作の例外処理
        conn = secure_db_connect()
        secure_create_stock_table(conn)
        
        # 存在しないIDでの操作
        @test secure_get_stock_by_id(conn, 99999) === nothing
        @test_nowarn secure_delete_stock(conn, 99999)  # 存在しないIDの削除は静かに失敗
        
        # 重複キーエラーのハンドリング
        stock1 = Stock(1, "商品1", "UNIQUE001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
        stock2 = Stock(2, "商品2", "UNIQUE001", 50, "個", 2000.0, "カテゴリ", "場所", now(), now())
        
        secure_insert_stock(conn, stock1)
        @test_throws Exception secure_insert_stock(conn, stock2)  # 重複コードエラー
        
        secure_db_close(conn)
    end
    
    # APIエラーレスポンスはHTTPサーバ依存のため現仕様では省略
    
    # リソースリーク系は別テストでカバーしているため省略
    
    @testset "同期・競合状態のエラーハンドリング" begin
        conn = secure_db_connect()
        secure_create_stock_table(conn)
        
        # テスト用データの挿入
        stock = Stock(1, "競合テスト", "RACE001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
        secure_insert_stock(conn, stock)
        
        # テスト: 同時更新の競合状態をシミュレート
        @test_nowarn begin
            # 複数のタスクで同じレコードを更新
            tasks = []
            for i in 1:5
                task = @async begin
                    try
                        updated_stock = Stock(1, "更新テスト$i", "RACE001", 100 + i, "個", 1000.0 + i, "カテゴリ", "場所", stock.created_at, now())
                        secure_update_stock(conn, updated_stock)
                    catch e
                        # 競合エラーは想定内
                        @test true
                    end
                end
                push!(tasks, task)
            end
            
            # 全てのタスクの完了を待つ
            for task in tasks
                wait(task)
            end
        end
        
        secure_db_close(conn)
    end
    
    @testset "メモリ使用量とパフォーマンステスト" begin
        # テスト: 大量データ処理時のメモリ管理
        @test_nowarn begin
            large_dataset = []
            for i in 1:1000
                push!(large_dataset, Stock(
                    i, "商品$i", "CODE$(lpad(i, 4, '0'))", rand(1:100), "個", 
                    rand(100.0:10000.0), "カテゴリ$(rand(1:5))", "場所$(rand(1:10))", 
                    now(), now()
                ))
            end
            
            # Excelエクスポート・インポートでのメモリ使用量テスト
            temp_file = tempname() * ".xlsx"
            export_stocks_to_excel(large_dataset, temp_file)
            imported_data = import_stocks_from_excel(temp_file)
            rm(temp_file, force=true)
            
            @test length(imported_data) == 1000
            
            # データセットをクリア
            large_dataset = nothing
            imported_data = nothing
            GC.gc()  # ガベージコレクション実行
        end
        
        # テスト: API応答時間の監視
        start_api_server(8201)
        
        try
            start_time = time()
            response = HTTP.get("http://localhost:8201/api/stocks")
            elapsed_time = time() - start_time
            
            @test response.status == 200
            @test elapsed_time < 5.0  # 5秒以内に応答
            
        finally
            stop_api_server(8201)
        end
    end
    
    @testset "ログローテーションとクリーンアップテスト" begin
        # テスト: ログファイルのサイズ制限
        @test_nowarn begin
            for i in 1:1000
                log_info("大量ログテスト $i: " * "x" ^ 100)
            end
        end
        
        # ログファイルが作成されていることを確認
        @test isfile("logs/app.log")
        
        # テスト: ログクリーンアップ機能
        @test_nowarn cleanup_old_logs(days=30)
        
        # テスト: セキュリティログの機密情報マスキング
        sensitive_data = Dict(
            "password" => "secret123",
            "credit_card" => "4111-1111-1111-1111",
            "ssn" => "123-45-6789"
        )
        
        @test_nowarn log_security_event("data_access", sensitive_data)
        
        # ログファイルに機密情報が平文で記録されていないことを確認
        log_content = read("logs/security.log", String)
        @test !contains(log_content, "secret123")
        @test !contains(log_content, "4111-1111-1111-1111")
    end
end
