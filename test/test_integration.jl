using Test
using HTTP
using JSON3
using Dates

# 必要な関数をインポート
using .InventorySystem: start_server, shutdown_system, system_info, Stock

@testset "Integration Tests" begin
    
    @testset "エンドツーエンド在庫管理フロー" begin
        # テスト環境の初期化
        init_logging()
        init_auth_database()
        init_connection_pool(max_connections=5)
        
        try
            # 1. ユーザー登録・認証
            admin_user = create_user("admin_test", "AdminPass123!", "admin@test.com", "admin")
            manager_user = create_user("manager_test", "ManagerPass123!", "manager@test.com", "manager")
            user_user = create_user("user_test", "UserPass123!", "user@test.com", "user")
            
            # 2. 管理者でログイン
            admin_auth = authenticate_user("admin_test", "AdminPass123!")
            @test admin_auth !== nothing
            admin_token = admin_auth.token
            
            # 3. APIサーバー起動
            start_api_server(8300)
            
            # 4. 認証付きAPI呼び出し
            headers = ["Authorization" => "Bearer $admin_token", "Content-Type" => "application/json"]
            
            # 5. 在庫データの作成（管理者権限）
            stock_data = Dict(
                "name" => "統合テスト商品",
                "code" => "INT001",
                "quantity" => 100,
                "unit" => "個",
                "price" => 1500.0,
                "category" => "統合テストカテゴリ",
                "location" => "TEST-1-1"
            )
            
            create_response = HTTP.post(
                "http://localhost:8300/api/stocks",
                headers=headers,
                body=JSON3.write(stock_data)
            )
            @test create_response.status == 201
            
            created_stock = JSON3.read(create_response.body)
            stock_id = created_stock.stock.id
            
            # 6. 在庫データの取得
            get_response = HTTP.get("http://localhost:8300/api/stocks/$stock_id", headers=headers)
            @test get_response.status == 200
            
            retrieved_stock = JSON3.read(get_response.body)
            @test retrieved_stock.stock.name == "統合テスト商品"
            
            # 7. 在庫データの更新
            update_data = Dict("quantity" => 150, "price" => 1800.0)
            
            update_response = HTTP.put(
                "http://localhost:8300/api/stocks/$stock_id",
                headers=headers,
                body=JSON3.write(update_data)
            )
            @test update_response.status == 200
            
            updated_stock = JSON3.read(update_response.body)
            @test updated_stock.stock.quantity == 150
            @test updated_stock.stock.price == 1800.0
            
            # 8. 一般ユーザーでの権限テスト
            user_auth = authenticate_user("user_test", "UserPass123!")
            user_token = user_auth.token
            user_headers = ["Authorization" => "Bearer $user_token", "Content-Type" => "application/json"]
            
            # 一般ユーザーは作成不可
            forbidden_response = HTTP.post(
                "http://localhost:8300/api/stocks",
                headers=user_headers,
                body=JSON3.write(stock_data),
                status_exception=false
            )
            @test forbidden_response.status == 403
            
            # 一般ユーザーは閲覧可能
            user_get_response = HTTP.get("http://localhost:8300/api/stocks", headers=user_headers)
            @test user_get_response.status == 200
            
            # 9. Excel エクスポート・インポートのテスト
            export_response = HTTP.get("http://localhost:8300/api/excel/export", headers=headers)
            @test export_response.status == 200
            @test HTTP.header(export_response, "Content-Type") == "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            
            # 10. 在庫削除（管理者権限）
            delete_response = HTTP.delete("http://localhost:8300/api/stocks/$stock_id", headers=headers)
            @test delete_response.status == 204
            
            # 削除確認
            deleted_check = HTTP.get("http://localhost:8300/api/stocks/$stock_id", headers=headers, status_exception=false)
            @test deleted_check.status == 404
            
        finally
            # クリーンアップ
            stop_api_server(8300)
            cleanup_connection_pool()
            delete_user("admin_test")
            delete_user("manager_test")
            delete_user("user_test")
        end
    end
    
    @testset "大量データ処理の統合テスト" begin
        init_connection_pool(max_connections=10)
        
        try
            conn = get_connection_from_pool()
            secure_create_stock_table(conn)
            
            # 大量データの作成
            large_dataset = []
            for i in 1:1000
                stock = Stock(
                    i,
                    "大量テスト商品$i",
                    "BULK$(lpad(i, 4, '0'))",
                    rand(1:1000),
                    "個",
                    rand(100.0:10000.0),
                    "大量テストカテゴリ$(rand(1:10))",
                    "BULK-$(rand(1:5))-$(rand(1:10))",
                    now(),
                    now()
                )
                push!(large_dataset, stock)
            end
            
            # バッチ挿入のパフォーマンステスト
            start_time = time()
            
            with_transaction(conn) do
                for stock in large_dataset
                    secure_insert_stock(conn, stock)
                end
            end
            
            insert_time = time() - start_time
            @test insert_time < 30.0  # 30秒以内で1000件挿入
            
            log_info("大量データ挿入完了", Dict(
                "records" => length(large_dataset),
                "time_seconds" => insert_time
            ))
            
            # 大量データの検索パフォーマンステスト
            start_time = time()
            all_stocks = secure_get_all_stocks(conn)
            search_time = time() - start_time
            
            @test length(all_stocks) == 1000
            @test search_time < 5.0  # 5秒以内で1000件検索
            
            # カテゴリ別検索
            start_time = time()
            category_stocks = secure_get_stocks_by_category(conn, "大量テストカテゴリ1")
            category_search_time = time() - start_time
            
            @test category_search_time < 2.0  # 2秒以内でカテゴリ検索
            
            # Excel エクスポートのパフォーマンステスト
            temp_file = tempname() * ".xlsx"
            start_time = time()
            export_stocks_to_excel(all_stocks, temp_file)
            export_time = time() - start_time
            
            @test export_time < 10.0  # 10秒以内で1000件エクスポート
            @test isfile(temp_file)
            
            # Excel インポートのパフォーマンステスト
            start_time = time()
            imported_stocks = import_stocks_from_excel(temp_file)
            import_time = time() - start_time
            
            @test import_time < 10.0  # 10秒以内で1000件インポート
            @test length(imported_stocks) == 1000
            
            # クリーンアップ
            rm(temp_file, force=true)
            return_connection_to_pool(conn)
            
        finally
            cleanup_connection_pool()
        end
    end
    
    @testset "障害回復とエラーハンドリングの統合テスト" begin
        init_connection_pool(max_connections=3)
        
        try
            # 正常な操作
            conn = get_connection_from_pool()
            secure_create_stock_table(conn)
            
            stock = Stock(1, "障害テスト", "FAIL001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
            secure_insert_stock(conn, stock)
            
            # 接続プールの健全性テスト
            @test is_connection_healthy(conn) == true
            
            # 意図的に接続を破損
            DuckDB.close(conn)
            @test is_connection_healthy(conn) == false
            
            # プールに破損した接続を返却
            return_connection_to_pool(conn)
            
            # プールの自動回復をテスト
            recover_connection_pool()
            
            # 新しい正常な接続が取得できることを確認
            new_conn = get_connection_from_pool()
            @test is_connection_healthy(new_conn) == true
            
            # データが保持されていることを確認
            stocks = secure_get_all_stocks(new_conn)
            @test length(stocks) >= 1
            
            return_connection_to_pool(new_conn)
            
        finally
            cleanup_connection_pool()
        end
    end
    
    @testset "セキュリティ統合テスト" begin
        init_auth_database()
        
        try
            # SQLインジェクション攻撃の統合テスト
            conn = secure_db_connect()
            secure_create_stock_table(conn)
            
            # 正常なデータを挿入
            normal_stock = Stock(1, "正常商品", "NORMAL001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
            secure_insert_stock(conn, normal_stock)
            
            # 悪意のある検索を試行
            malicious_queries = [
                "'; DROP TABLE stocks; --",
                "' UNION SELECT * FROM users --",
                "' OR 1=1 --"
            ]
            
            for malicious_query in malicious_queries
                @test_nowarn begin
                    # 攻撃が失敗することを確認
                    result = secure_get_stocks_by_category(conn, malicious_query)
                    @test length(result) == 0
                end
                
                # テーブルがまだ存在することを確認
                @test secure_table_exists(conn, "stocks") == true
            end
            
            secure_db_close(conn)
            
            # 認証攻撃の統合テスト
            test_user = create_user("security_test", "SecurePass123!", "security@test.com", "user")
            
            # ブルートフォース攻撃をシミュレート
            for i in 1:6  # 5回失敗でロック
                result = authenticate_user("security_test", "wrongpassword")
                @test result === nothing
            end
            
            # アカウントがロックされることを確認
            @test is_account_locked("security_test") == true
            
            # 正しいパスワードでもログインできないことを確認
            locked_result = authenticate_user("security_test", "SecurePass123!")
            @test locked_result === nothing
            
            # アカウントロック解除
            unlock_account("security_test")
            
            # 解除後は正常にログインできることを確認
            unlocked_result = authenticate_user("security_test", "SecurePass123!")
            @test unlocked_result !== nothing
            
            delete_user("security_test")
            
        finally
            # クリーンアップ
        end
    end
    
    @testset "並行処理とスレッドセーフティテスト" begin
        init_connection_pool(max_connections=15)
        
        try
            # 複数スレッドでの同時データベースアクセス
            tasks = []
            results = []
            
            # 20個の並行タスクを作成
            for i in 1:20
                task = @async begin
                    try
                        conn = get_connection_from_pool()
                        
                        # テーブル作成（既に存在する場合はスキップ）
                        secure_create_stock_table(conn)
                        
                        # ユニークなデータを挿入
                        stock = Stock(
                            i + 1000,  # IDの重複を避ける
                            "並行テスト商品$i",
                            "CONC$(lpad(i, 3, '0'))",
                            rand(1:100),
                            "個",
                            rand(100.0:5000.0),
                            "並行カテゴリ",
                            "CONC-1-$i",
                            now(),
                            now()
                        )
                        
                        secure_insert_stock(conn, stock)
                        
                        # データの読み取り
                        retrieved = secure_get_stock_by_id(conn, i + 1000)
                        
                        return_connection_to_pool(conn)
                        
                        return retrieved !== nothing
                        
                    catch e
                        log_error("並行処理テストでエラー", Dict(
                            "task_id" => i,
                            "error" => string(e)
                        ))
                        return false
                    end
                end
                push!(tasks, task)
            end
            
            # 全てのタスクの完了を待つ
            for task in tasks
                result = fetch(task)
                push!(results, result)
            end
            
            # 全てのタスクが成功することを確認
            success_count = count(results)
            @test success_count >= 18  # 90%以上の成功率
            
            log_info("並行処理テスト完了", Dict(
                "total_tasks" => length(tasks),
                "successful_tasks" => success_count,
                "success_rate" => success_count / length(tasks)
            ))
            
        finally
            cleanup_connection_pool()
        end
    end
    
    @testset "フルシステム負荷テスト" begin
        # システム全体の負荷テスト
        init_auth_database()
        init_connection_pool(max_connections=20)
        
        try
            # 複数ユーザーの作成
            users = []
            for i in 1:5
                user = create_user("load_user_$i", "LoadPass123!", "load$i@test.com", "user")
                push!(users, user)
            end
            
            # 管理者ユーザー
            admin = create_user("load_admin", "AdminPass123!", "load_admin@test.com", "admin")
            admin_auth = authenticate_user("load_admin", "AdminPass123!")
            
            start_api_server(8400)
            
            # 複数ユーザーでの同時API呼び出し
            api_tasks = []
            
            for user in users
                task = @async begin
                    try
                        # ユーザー認証
                        auth_result = authenticate_user(user.username, "LoadPass123!")
                        if auth_result === nothing
                            return false
                        end
                        
                        headers = ["Authorization" => "Bearer $(auth_result.token)"]
                        
                        # API呼び出し（複数回）
                        for j in 1:10
                            response = HTTP.get("http://localhost:8400/api/stocks", headers=headers)
                            if response.status != 200
                                return false
                            end
                            sleep(0.1)  # 短い間隔
                        end
                        
                        return true
                        
                    catch e
                        log_error("負荷テストAPIエラー", Dict(
                            "user" => user.username,
                            "error" => string(e)
                        ))
                        return false
                    end
                end
                push!(api_tasks, task)
            end
            
            # データベース負荷タスク
            db_tasks = []
            for i in 1:10
                task = @async begin
                    try
                        conn = get_connection_from_pool()
                        
                        for j in 1:20
                            stock = Stock(
                                i * 1000 + j,
                                "負荷テスト商品$(i)_$(j)",
                                "LOAD$(lpad(i, 2, '0'))$(lpad(j, 2, '0'))",
                                rand(1:500),
                                "個",
                                rand(500.0:5000.0),
                                "負荷テストカテゴリ",
                                "LOAD-$i-$j",
                                now(),
                                now()
                            )
                            secure_insert_stock(conn, stock)
                        end
                        
                        return_connection_to_pool(conn)
                        return true
                        
                    catch e
                        log_error("負荷テストDB エラー", Dict(
                            "task_id" => i,
                            "error" => string(e)
                        ))
                        return false
                    end
                end
                push!(db_tasks, task)
            end
            
            # 全てのタスクの完了を待つ
            start_time = time()
            
            api_results = [fetch(task) for task in api_tasks]
            db_results = [fetch(task) for task in db_tasks]
            
            total_time = time() - start_time
            
            # 結果の検証
            api_success_rate = count(api_results) / length(api_results)
            db_success_rate = count(db_results) / length(db_results)
            
            @test api_success_rate >= 0.9  # 90%以上の成功率
            @test db_success_rate >= 0.9   # 90%以上の成功率
            @test total_time < 60.0         # 60秒以内で完了
            
            log_info("フルシステム負荷テスト完了", Dict(
                "total_time" => total_time,
                "api_success_rate" => api_success_rate,
                "db_success_rate" => db_success_rate,
                "api_tasks" => length(api_tasks),
                "db_tasks" => length(db_tasks)
            ))
            
        finally
            stop_api_server(8400)
            cleanup_connection_pool()
            
            # ユーザークリーンアップ
            for user in users
                delete_user(user.username)
            end
            delete_user("load_admin")
        end
    end
end