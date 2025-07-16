module ConnectionPool

using DuckDB
using Dates
using Base.Threads
using ..ErrorHandling

export init_connection_pool, cleanup_connection_pool, get_connection_from_pool,
       return_connection_to_pool, get_pool_statistics, get_pool_configuration,
       is_connection_healthy, cleanup_idle_connections, with_transaction,
       should_alert_high_usage, detect_connection_leaks, recover_connection_pool

# 接続情報構造体
mutable struct ConnectionInfo
    connection::DuckDB.DB
    created_at::DateTime
    last_used::DateTime
    in_use::Bool
    is_healthy::Bool
    use_count::Int
end

# プール設定構造体
mutable struct PoolConfig
    max_connections::Int
    min_connections::Int
    connection_timeout::Int  # 秒
    idle_timeout::Int        # 秒
    health_check_interval::Int  # 秒
    max_connection_age::Int     # 秒
    database_path::String
end

# グローバルプール状態
const POOL_LOCK = ReentrantLock()
const CONNECTION_POOL = Vector{ConnectionInfo}()
const POOL_CONFIG = Ref{Union{PoolConfig, Nothing}}(nothing)
const POOL_STATS = Dict{Symbol, Any}()

function init_connection_pool(config::Dict = Dict(); 
                            max_connections::Int = 10,
                            min_connections::Int = 2,
                            connection_timeout::Int = 30,
                            idle_timeout::Int = 300,
                            health_check_interval::Int = 60,
                            max_connection_age::Int = 3600,
                            database_path::String = ":memory:")
    """
    接続プールを初期化
    """
    lock(POOL_LOCK) do
        try
            # 設定の作成
            if !isempty(config)
                POOL_CONFIG[] = PoolConfig(
                    get(config, :max_connections, max_connections),
                    get(config, :min_connections, min_connections),
                    get(config, :connection_timeout, connection_timeout),
                    get(config, :idle_timeout, idle_timeout),
                    get(config, :health_check_interval, health_check_interval),
                    get(config, :max_connection_age, max_connection_age),
                    get(config, :database_path, database_path)
                )
            else
                POOL_CONFIG[] = PoolConfig(
                    max_connections, min_connections, connection_timeout,
                    idle_timeout, health_check_interval, max_connection_age, database_path
                )
            end
            
            # 既存のプールをクリーンアップ
            cleanup_connection_pool_internal()
            
            # 最小接続数分の接続を事前作成
            for i in 1:POOL_CONFIG[].min_connections
                conn_info = create_new_connection()
                if conn_info !== nothing
                    push!(CONNECTION_POOL, conn_info)
                end
            end
            
            # 統計情報の初期化
            update_pool_statistics()
            
            # バックグラウンドタスクの開始
            start_background_tasks()
            
            log_info("接続プールが初期化されました", Dict(
                "max_connections" => POOL_CONFIG[].max_connections,
                "min_connections" => POOL_CONFIG[].min_connections,
                "initial_connections" => length(CONNECTION_POOL)
            ))
            
        catch e
            log_error("接続プール初期化でエラーが発生しました", Dict("error" => string(e)))
            rethrow(e)
        end
    end
end

function cleanup_connection_pool()
    """
    接続プールをクリーンアップ（公開関数）
    """
    lock(POOL_LOCK) do
        cleanup_connection_pool_internal()
    end
end

function cleanup_connection_pool_internal()
    """
    接続プールをクリーンアップ（内部関数）
    """
    try
        for conn_info in CONNECTION_POOL
            try
                if conn_info.is_healthy
                    DuckDB.close(conn_info.connection)
                end
            catch e
                log_warning("接続のクリーンアップ中にエラーが発生しました", Dict("error" => string(e)))
            end
        end
        
        empty!(CONNECTION_POOL)
        POOL_CONFIG[] = nothing
        
        log_info("接続プールがクリーンアップされました")
        
    catch e
        log_error("接続プールクリーンアップでエラーが発生しました", Dict("error" => string(e)))
    end
end

function create_new_connection()::Union{ConnectionInfo, Nothing}
    """
    新しい接続を作成
    """
    try
        if POOL_CONFIG[] === nothing
            throw(ArgumentError("接続プールが初期化されていません"))
        end
        
        conn = DuckDB.DB(POOL_CONFIG[].database_path)
        current_time = now()
        
        return ConnectionInfo(
            conn, current_time, current_time, false, true, 0
        )
        
    catch e
        log_error("新しい接続の作成に失敗しました", Dict("error" => string(e)))
        return nothing
    end
end

function get_connection_from_pool(timeout::Int = 30)::DuckDB.DB
    """
    プールから接続を取得
    """
    start_time = time()
    
    while (time() - start_time) < timeout
        lock(POOL_LOCK) do
            try
                # 利用可能な接続を検索
                for conn_info in CONNECTION_POOL
                    if !conn_info.in_use && conn_info.is_healthy
                        # 接続の健全性チェック
                        if is_connection_healthy(conn_info.connection)
                            conn_info.in_use = true
                            conn_info.last_used = now()
                            conn_info.use_count += 1
                            
                            update_pool_statistics()
                            
                            log_debug("プールから接続を取得しました", Dict(
                                "use_count" => conn_info.use_count
                            ))
                            
                            return conn_info.connection
                        else
                            # 不正な接続をマーク
                            conn_info.is_healthy = false
                        end
                    end
                end
                
                # 利用可能な接続がない場合、新しい接続を作成
                if length(CONNECTION_POOL) < POOL_CONFIG[].max_connections
                    new_conn_info = create_new_connection()
                    if new_conn_info !== nothing
                        new_conn_info.in_use = true
                        new_conn_info.last_used = now()
                        new_conn_info.use_count = 1
                        
                        push!(CONNECTION_POOL, new_conn_info)
                        update_pool_statistics()
                        
                        log_debug("新しい接続を作成しました")
                        
                        return new_conn_info.connection
                    end
                end
                
            catch e
                log_error("接続取得中にエラーが発生しました", Dict("error" => string(e)))
                rethrow(e)
            end
        end
        
        # 短時間待機してリトライ
        sleep(0.1)
    end
    
    # タイムアウト
    log_warning("接続取得がタイムアウトしました", Dict("timeout" => timeout))
    throw(ArgumentError("接続プールから接続を取得できませんでした（タイムアウト）"))
end

function return_connection_to_pool(connection::DuckDB.DB)
    """
    接続をプールに返却
    """
    lock(POOL_LOCK) do
        try
            for conn_info in CONNECTION_POOL
                if conn_info.connection === connection
                    if conn_info.in_use
                        # 接続の健全性チェック
                        if is_connection_healthy(connection)
                            conn_info.in_use = false
                            conn_info.last_used = now()
                            log_debug("接続をプールに返却しました")
                        else
                            # 不正な接続を削除
                            conn_info.is_healthy = false
                            try
                                DuckDB.close(connection)
                            catch
                                # 既に閉じられている可能性がある
                            end
                            
                            # プールから削除
                            filter!(ci -> ci !== conn_info, CONNECTION_POOL)
                            log_warning("不正な接続を削除しました")
                            
                            # 最小接続数を維持
                            maintain_minimum_connections()
                        end
                        
                        update_pool_statistics()
                        return
                    end
                end
            end
            
            log_warning("返却対象の接続がプールに見つかりませんでした")
            
        catch e
            log_error("接続返却中にエラーが発生しました", Dict("error" => string(e)))
        end
    end
end

function is_connection_healthy(connection::DuckDB.DB)::Bool
    """
    接続の健全性をチェック
    """
    try
        # 簡単なクエリを実行して接続をテスト
        result = DuckDB.execute(connection, "SELECT 1 as health_check")
        return true
    catch
        return false
    end
end

function cleanup_idle_connections()
    """
    アイドル接続をクリーンアップ
    """
    lock(POOL_LOCK) do
        try
            if POOL_CONFIG[] === nothing
                return
            end
            
            current_time = now()
            idle_threshold = Second(POOL_CONFIG[].idle_timeout)
            age_threshold = Second(POOL_CONFIG[].max_connection_age)
            
            connections_to_remove = []
            
            for conn_info in CONNECTION_POOL
                # アイドル時間または接続年数をチェック
                idle_time = current_time - conn_info.last_used
                connection_age = current_time - conn_info.created_at
                
                if !conn_info.in_use && (idle_time > idle_threshold || connection_age > age_threshold)
                    push!(connections_to_remove, conn_info)
                end
            end
            
            # 最小接続数を維持しながら接続を削除
            current_count = length(CONNECTION_POOL)
            min_connections = POOL_CONFIG[].min_connections
            
            for conn_info in connections_to_remove
                if current_count > min_connections
                    try
                        DuckDB.close(conn_info.connection)
                    catch
                        # 既に閉じられている可能性がある
                    end
                    
                    filter!(ci -> ci !== conn_info, CONNECTION_POOL)
                    current_count -= 1
                    
                    log_debug("アイドル接続を削除しました")
                end
            end
            
            update_pool_statistics()
            
        catch e
            log_error("アイドル接続クリーンアップでエラーが発生しました", Dict("error" => string(e)))
        end
    end
end

function maintain_minimum_connections()
    """
    最小接続数を維持
    """
    if POOL_CONFIG[] === nothing
        return
    end
    
    current_count = length(CONNECTION_POOL)
    min_connections = POOL_CONFIG[].min_connections
    
    while current_count < min_connections
        new_conn_info = create_new_connection()
        if new_conn_info !== nothing
            push!(CONNECTION_POOL, new_conn_info)
            current_count += 1
            log_debug("最小接続数維持のため新しい接続を作成しました")
        else
            break
        end
    end
end

function update_pool_statistics()
    """
    プール統計情報を更新
    """
    try
        total_connections = length(CONNECTION_POOL)
        active_connections = count(ci -> ci.in_use, CONNECTION_POOL)
        idle_connections = total_connections - active_connections
        healthy_connections = count(ci -> ci.is_healthy, CONNECTION_POOL)
        
        POOL_STATS[:total_connections] = total_connections
        POOL_STATS[:active_connections] = active_connections
        POOL_STATS[:idle_connections] = idle_connections
        POOL_STATS[:healthy_connections] = healthy_connections
        POOL_STATS[:last_updated] = now()
        
        if total_connections > 0
            POOL_STATS[:usage_rate] = active_connections / total_connections
        else
            POOL_STATS[:usage_rate] = 0.0
        end
        
    catch e
        log_error("プール統計更新でエラーが発生しました", Dict("error" => string(e)))
    end
end

function get_pool_statistics()::Dict{Symbol, Any}
    """
    プール統計情報を取得
    """
    lock(POOL_LOCK) do
        update_pool_statistics()
        return copy(POOL_STATS)
    end
end

function get_pool_configuration()::Dict{Symbol, Any}
    """
    プール設定を取得
    """
    if POOL_CONFIG[] === nothing
        return Dict{Symbol, Any}()
    end
    
    config = POOL_CONFIG[]
    return Dict(
        :max_connections => config.max_connections,
        :min_connections => config.min_connections,
        :connection_timeout => config.connection_timeout,
        :idle_timeout => config.idle_timeout,
        :health_check_interval => config.health_check_interval,
        :max_connection_age => config.max_connection_age,
        :database_path => config.database_path
    )
end

function with_transaction(func::Function, connection::DuckDB.DB)
    """
    トランザクション付きで関数を実行
    """
    try
        DuckDB.execute(connection, "BEGIN TRANSACTION")
        
        result = func()
        
        DuckDB.execute(connection, "COMMIT")
        log_debug("トランザクションをコミットしました")
        
        return result
        
    catch e
        try
            DuckDB.execute(connection, "ROLLBACK")
            log_debug("トランザクションをロールバックしました")
        catch rollback_error
            log_error("ロールバック中にエラーが発生しました", Dict("error" => string(rollback_error)))
        end
        
        log_error("トランザクション実行中にエラーが発生しました", Dict("error" => string(e)))
        rethrow(e)
    end
end

function should_alert_high_usage(usage_rate::Float64, threshold::Float64 = 0.8)::Bool
    """
    高使用率アラートが必要かチェック
    """
    return usage_rate >= threshold
end

function detect_connection_leaks(max_hold_time::Float64 = 300.0)::Vector{ConnectionInfo}
    """
    接続リークを検出
    """
    lock(POOL_LOCK) do
        leaked_connections = ConnectionInfo[]
        current_time = now()
        
        for conn_info in CONNECTION_POOL
            if conn_info.in_use
                hold_time = (current_time - conn_info.last_used).value / 1000.0  # 秒に変換
                if hold_time > max_hold_time
                    push!(leaked_connections, conn_info)
                    log_warning("接続リークを検出しました", Dict(
                        "hold_time" => hold_time,
                        "use_count" => conn_info.use_count
                    ))
                end
            end
        end
        
        return leaked_connections
    end
end

function recover_connection_pool()
    """
    プールの回復処理
    """
    lock(POOL_LOCK) do
        try
            log_info("接続プールの回復処理を開始します")
            
            # 全ての不正な接続を削除
            healthy_connections = ConnectionInfo[]
            
            for conn_info in CONNECTION_POOL
                if conn_info.is_healthy && is_connection_healthy(conn_info.connection)
                    push!(healthy_connections, conn_info)
                else
                    try
                        DuckDB.close(conn_info.connection)
                    catch
                        # 既に閉じられている
                    end
                end
            end
            
            # プールを更新
            empty!(CONNECTION_POOL)
            append!(CONNECTION_POOL, healthy_connections)
            
            # 最小接続数まで補充
            maintain_minimum_connections()
            
            update_pool_statistics()
            
            log_info("接続プールが回復しました", Dict(
                "healthy_connections" => length(CONNECTION_POOL)
            ))
            
        catch e
            log_error("接続プール回復処理でエラーが発生しました", Dict("error" => string(e)))
        end
    end
end

function start_background_tasks()
    """
    バックグラウンドタスクを開始
    """
    if POOL_CONFIG[] === nothing
        return
    end
    
    # 健全性チェックタスク
    @async begin
        while POOL_CONFIG[] !== nothing
            try
                sleep(POOL_CONFIG[].health_check_interval)
                cleanup_idle_connections()
                
                # 高使用率アラートチェック
                stats = get_pool_statistics()
                if should_alert_high_usage(stats[:usage_rate])
                    log_warning("接続プールの使用率が高くなっています", Dict(
                        "usage_rate" => stats[:usage_rate],
                        "active_connections" => stats[:active_connections],
                        "total_connections" => stats[:total_connections]
                    ))
                end
                
                # 接続リーク検出
                leaked = detect_connection_leaks()
                if !isempty(leaked)
                    log_security_event("connection_leak_detected", Dict(
                        "leaked_count" => length(leaked)
                    ))
                end
                
            catch e
                log_error("バックグラウンドタスクでエラーが発生しました", Dict("error" => string(e)))
            end
        end
    end
end

end