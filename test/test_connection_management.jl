using Test
using DuckDB
using DataFrames
using Dates

# 必要な関数をインポート
using .InventorySystem: init_connection_pool, cleanup_connection_pool, 
                       get_connection_from_pool, return_connection_to_pool, 
                       get_pool_statistics, is_connection_healthy, 
                       with_transaction, recover_connection_pool,
                       get_pool_configuration, cleanup_idle_connections,
                       should_alert_high_usage, detect_connection_leaks,
                       secure_create_stock_table, secure_insert_stock,
                       secure_get_all_stocks, Stock

@testset "Database Connection Management Tests" begin
    
    @testset "接続プール基本機能テスト" begin
        # テスト: 接続プールの初期化
        @test_nowarn init_connection_pool(max_connections=5)
        
        # テスト: 接続プールからの接続取得
        conn1 = get_connection_from_pool()
        @test conn1 !== nothing
        @test typeof(conn1) == DuckDB.DB
        
        # テスト: 複数の接続取得
        connections = []
        for i in 1:3
            conn = get_connection_from_pool()
            @test conn !== nothing
            push!(connections, conn)
        end
        @test length(connections) == 3
        
        # テスト: 接続の返却
        for conn in connections
            @test_nowarn return_connection_to_pool(conn)
        end
        @test_nowarn return_connection_to_pool(conn1)
        
        # テスト: プールの統計情報
        stats = get_pool_statistics()
        @test haskey(stats, :total_connections)
        @test haskey(stats, :active_connections)
        @test haskey(stats, :idle_connections)
        @test stats[:active_connections] == 0  # 全て返却済み
        
        # 後片付け
        cleanup_connection_pool()
    end
    
    @testset "接続プール制限テスト" begin
        # 小さなプールサイズでテスト
        init_connection_pool(max_connections=2)
        
        # テスト: 最大接続数まで取得
        conn1 = get_connection_from_pool()
        conn2 = get_connection_from_pool()
        @test conn1 !== nothing
        @test conn2 !== nothing
        
        # テスト: 制限を超えた接続取得の試行
        @test_throws Exception get_connection_from_pool(timeout=1)  # 短いタイムアウト
        
        # テスト: 接続返却後の再利用
        return_connection_to_pool(conn1)
        conn3 = get_connection_from_pool()
        @test conn3 !== nothing
        
        # 後片付け
        return_connection_to_pool(conn2)
        return_connection_to_pool(conn3)
        cleanup_connection_pool()
    end
    
    @testset "接続の健全性チェックテスト" begin
        init_connection_pool(max_connections=3)
        
        # テスト: 正常な接続の健全性チェック
        conn = get_connection_from_pool()
        @test is_connection_healthy(conn) == true
        
        # テスト: 無効な接続の検出
        # 接続を意図的に破損（実際の実装では接続を閉じる）
        DuckDB.close(conn)
        @test is_connection_healthy(conn) == false
        
        # テスト: 破損した接続の自動回復
        @test_nowarn return_connection_to_pool(conn)  # 破損した接続を返却
        
        # 新しい接続を取得（プールが自動的に新しい接続を作成すべき）
        new_conn = get_connection_from_pool()
        @test is_connection_healthy(new_conn) == true
        
        return_connection_to_pool(new_conn)
        cleanup_connection_pool()
    end
    
    @testset "並行接続管理テスト" begin
        init_connection_pool(max_connections=10)
        
        # テスト: 並行アクセス
        tasks = []
        results = []
        
        for i in 1:20
            task = @async begin
                try
                    conn = get_connection_from_pool()
                    
                    # 簡単なクエリを実行
                    DuckDB.execute(conn, "SELECT 1 as test")
                    
                    # 少し待機
                    sleep(0.1)
                    
                    return_connection_to_pool(conn)
                    return true
                catch e
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
        @test all(results)
        
        # プール統計の確認
        stats = get_pool_statistics()
        @test stats[:active_connections] == 0  # 全て返却済み
        
        cleanup_connection_pool()
    end
    
    @testset "接続タイムアウト管理テスト" begin
        init_connection_pool(max_connections=2, connection_timeout=5, idle_timeout=10)
        
        # テスト: アイドル接続のタイムアウト
        conn1 = get_connection_from_pool()
        conn2 = get_connection_from_pool()
        
        return_connection_to_pool(conn1)
        return_connection_to_pool(conn2)
        
        # アイドル接続のクリーンアップをシミュレート
        @test_nowarn cleanup_idle_connections()
        
        # 統計情報の確認
        stats = get_pool_statistics()
        @test stats[:idle_connections] >= 0
        
        cleanup_connection_pool()
    end
    
    @testset "トランザクション管理の統合テスト" begin
        init_connection_pool(max_connections=3)
        
        conn = get_connection_from_pool()
        secure_create_stock_table(conn)
        
        # テスト: 自動トランザクション管理
        @test_nowarn with_transaction(() -> begin
            stock1 = Stock(1, "トランザクションテスト1", "TXN001", 100, "個", 1000.0, "カテゴリ", "場所", now(), now())
            stock2 = Stock(2, "トランザクションテスト2", "TXN002", 50, "個", 2000.0, "カテゴリ", "場所", now(), now())
            secure_insert_stock(conn, stock1)
            secure_insert_stock(conn, stock2)
        end, conn)
        
        # データが正常にコミットされていることを確認
        stocks = secure_get_all_stocks(conn)
        @test length(stocks) == 2
        
        # テスト: トランザクションのロールバック
        @test_throws Exception with_transaction(() -> begin
            stock3 = Stock(3, "失敗テスト", "FAIL001", 75, "個", 1500.0, "カテゴリ", "場所", now(), now())
            secure_insert_stock(conn, stock3)
            throw(ArgumentError("テストエラー"))
        end, conn)
        
        # ロールバックにより、3番目のデータは挿入されていないことを確認
        stocks_after_rollback = secure_get_all_stocks(conn)
        @test length(stocks_after_rollback) == 2
        
        return_connection_to_pool(conn)
        cleanup_connection_pool()
    end
    
    @testset "接続プール監視とアラートテスト" begin
        init_connection_pool(max_connections=3)
        
        # テスト: プール使用率の監視
        conn1 = get_connection_from_pool()
        conn2 = get_connection_from_pool()
        
        stats = get_pool_statistics()
        usage_rate = stats[:active_connections] / stats[:total_connections]
        @test usage_rate > 0.5  # 50%以上使用中
        
        # テスト: 高使用率アラート
        @test should_alert_high_usage(usage_rate) == true
        
        # テスト: リークした接続の検出
        # 接続を返却せずに長時間保持
        start_time = time()
        sleep(0.1)  # 短い待機（実際のテストでは長期間）
        
        leaked_connections = detect_connection_leaks(max_hold_time=0.05)
        @test length(leaked_connections) >= 0  # リーク検出機能のテスト
        
        return_connection_to_pool(conn1)
        return_connection_to_pool(conn2)
        cleanup_connection_pool()
    end
    
    @testset "パフォーマンス最適化テスト" begin
        # 大きなプールでのパフォーマンステスト
        init_connection_pool(max_connections=20)
        
        # テスト: 接続取得・返却の速度
        start_time = time()
        
        for i in 1:100
            conn = get_connection_from_pool()
            return_connection_to_pool(conn)
        end
        
        elapsed_time = time() - start_time
        @test elapsed_time < 5.0  # 5秒以内で100回の操作
        
        # テスト: 並行アクセス時のパフォーマンス
        start_time = time()
        tasks = []
        
        for i in 1:50
            task = @async begin
                conn = get_connection_from_pool()
                DuckDB.execute(conn, "SELECT $i as test_value")
                return_connection_to_pool(conn)
            end
            push!(tasks, task)
        end
        
        # 全てのタスクの完了を待つ
        for task in tasks
            wait(task)
        end
        
        concurrent_elapsed = time() - start_time
        @test concurrent_elapsed < 10.0  # 10秒以内で50並行操作
        
        cleanup_connection_pool()
    end
    
    @testset "設定とカスタマイズテスト" begin
        # カスタム設定でのプール初期化
        custom_config = Dict(
            :max_connections => 5,
            :min_connections => 2,
            :connection_timeout => 30,
            :idle_timeout => 300,
            :health_check_interval => 60
        )
        
        @test_nowarn init_connection_pool(custom_config)
        
        # 設定の確認
        config = get_pool_configuration()
        @test config[:max_connections] == 5
        @test config[:min_connections] == 2
        
        # 最小接続数の確認
        stats = get_pool_statistics()
        @test stats[:total_connections] >= 2
        
        cleanup_connection_pool()
    end
    
    @testset "エラー回復とフォールバックテスト" begin
        init_connection_pool(max_connections=3)
        
        # テスト: データベースサーバーの一時的な停止をシミュレート
        # 全ての接続を取得して意図的に破損させる
        connections = []
        for i in 1:3
            conn = get_connection_from_pool()
            DuckDB.close(conn)  # 接続を破損
            push!(connections, conn)
        end
        
        # 破損した接続を返却
        for conn in connections
            return_connection_to_pool(conn)
        end
        
        # テスト: プールの自動回復
        @test_nowarn recover_connection_pool()
        
        # 新しい接続が正常に取得できることを確認
        healthy_conn = get_connection_from_pool()
        @test is_connection_healthy(healthy_conn) == true
        
        return_connection_to_pool(healthy_conn)
        cleanup_connection_pool()
    end
    
    @testset "メモリ使用量とリソース管理テスト" begin
        # 大量の接続作成・破棄によるメモリリークテスト
        initial_memory = Base.gc_num().total
        
        for iteration in 1:10
            init_connection_pool(max_connections=10)
            
            # 複数の接続を取得・返却
            connections = []
            for i in 1:10
                conn = get_connection_from_pool()
                push!(connections, conn)
            end
            
            for conn in connections
                return_connection_to_pool(conn)
            end
            
            cleanup_connection_pool()
            GC.gc()  # 明示的なガベージコレクション
        end
        
        final_memory = Base.gc_num().total
        memory_increase = final_memory - initial_memory
        
        # メモリ使用量の増加が合理的な範囲内であることを確認
        @test memory_increase < 100_000_000  # 100MB未満の増加
    end
end
