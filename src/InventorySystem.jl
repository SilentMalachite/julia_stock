module InventorySystem

using Dates

# === 正しい依存関係順序でモジュールをロード ===

# 1. 依存関係のない基本モジュール
include("models/Stock.jl")
using .StockModel

# 2. ユーティリティモジュール（他の多くのモジュールで使用）
include("utils/ErrorHandling.jl")
using .ErrorHandling

# 3. 認証システム（独立）
include("auth/AuthenticationSystem.jl")
using .AuthenticationSystem

# 4. データベース接続
include("database/DuckDBConnection.jl")
using .DuckDBConnection

# 5. 接続プール（ErrorHandlingに依存）
include("database/ConnectionPool.jl")
using .ConnectionPool

# 7. Excel操作（StockModelに依存）
include("excel/ExcelHandler.jl")
using .ExcelHandler

# 8. WebAPI（多くのモジュールに依存）
include("web/WebAPI.jl")
using .WebAPI

# 全てのエクスポートを再エクスポート
export Stock, add_quantity, reduce_quantity, filter_by_category, filter_out_of_stock,
       filter_low_stock, calculate_total_value, calculate_category_stats,
       # データベース接続関数
       db_connect, db_close, create_stock_table, table_exists,
       insert_stock, get_all_stocks, get_stock_by_id, update_stock, delete_stock,
       get_stocks_by_category, get_out_of_stock_items, get_low_stock_items,
       begin_transaction, commit_transaction, rollback_transaction, execute_query,
       # 認証システム
       init_auth_database, create_user, authenticate_user, delete_user, get_all_users,
       change_password, is_account_locked, unlock_account, 
       # エラーハンドリング
       init_logging, log_info, log_warning, log_error, log_debug, log_security_event,
       # 接続プール
       init_connection_pool, cleanup_connection_pool, get_connection_from_pool,
       return_connection_to_pool, get_pool_statistics, is_connection_healthy,
       with_transaction, recover_connection_pool, cleanup_idle_connections,
       get_pool_configuration, should_alert_high_usage, detect_connection_leaks,
       # Excel機能
       create_empty_excel, export_stocks_to_excel, import_stocks_from_excel,
       create_stock_template, get_excel_headers, validate_excel_format,
       # Web API
       start_api_server, stop_api_server, is_server_running, add_test_stock,
       # システム管理
       start_server, shutdown_system, system_info, ensure_default_admin

function start_server(port::Int = 8000)
    """
    統合在庫管理システムを起動
    """
    try
        println("=== Julia在庫管理システム v1.0.0 ===")
        println("システム初期化中...")
        
        # 1. ログシステムの初期化
        init_logging()
        log_info("システム起動開始", Dict("port" => port))
        
        # 2. 認証データベースの初期化
        println("認証システムを初期化中...")
        init_auth_database()
        log_info("認証システムが初期化されました")
        
        # 3. 接続プールの初期化
        println("データベース接続プールを初期化中...")
        init_connection_pool(
            max_connections = 20,
            min_connections = 5,
            connection_timeout = 30,
            database_path = "data/inventory.db"
        )
        log_info("接続プールが初期化されました")
        
        # 4. メインデータベースの初期化
        println("メインデータベースを初期化中...")
        conn = get_connection_from_pool()
        try
            create_stock_table(conn)
            log_info("在庫テーブルが準備されました")
        finally
            return_connection_to_pool(conn)
        end
        
        # 5. デフォルト管理者アカウントの確認・作成
        println("管理者アカウントを確認中...")
        ensure_default_admin()
        
        # 6. APIサーバーを起動
        println("Webサーバーを起動中... (ポート: $port)")
        start_api_server(port)
        
        println("\n✓ 在庫管理システムが正常に起動しました")
        println("\n🌐 API エンドポイント:")
        println("   - ベースURL: http://localhost:$port/api/")
        println("   - ヘルスチェック: http://localhost:$port/api/health")
        println("   - 在庫一覧: http://localhost:$port/api/stocks")
        println("\n🔐 認証:")
        println("   - ログイン: POST /api/auth/login")
        println("   - 管理者の初期化: 環境変数 ADMIN_DEFAULT_PASSWORD を使用（任意）")
        println("\n📖 ドキュメント: docs/API_SPECIFICATION.md")
        println("📋 運用マニュアル: docs/OPERATIONS_MANUAL.md")
        
        log_info("システム起動完了", Dict(
            "port" => port,
            "api_endpoint" => "http://localhost:$port/api/"
        ))
        
    catch e
        log_error("システム起動エラー", Dict("error" => string(e)))
        println("❌ システム起動中にエラーが発生しました: $(string(e))")
        rethrow(e)
    end
end

function ensure_default_admin()
    """
    デフォルト管理者アカウントの存在を確認し、なければ作成
    """
    try
        users = get_all_users()
        admin_exists = any(user -> user.role == "admin", users)

        if !admin_exists
            default_pw = get(ENV, "ADMIN_DEFAULT_PASSWORD", "")
            default_email = get(ENV, "ADMIN_DEFAULT_EMAIL", "admin@inventory.system")
            if !isempty(default_pw)
                # 最低要件チェック
                if length(default_pw) < 12 || !occursin(r"^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[!@#$%^&*]).{12,}$", default_pw)
                    log_warning("ADMIN_DEFAULT_PASSWORD が弱すぎるため管理者は作成されません")
                else
                    admin_user = create_user("admin", default_pw, default_email, "admin")
                    log_info("管理者アカウントを初期作成しました", Dict("username" => admin_user.username))
                end
            else
                log_info("管理者アカウントは未作成（ADMIN_DEFAULT_PASSWORD 未設定）")
            end
        else
            log_info("管理者アカウントが確認されました")
        end
    catch e
        log_warning("管理者アカウントの確認中にエラーが発生しました", Dict("error" => string(e)))
    end
end

function shutdown_system()
    """
    システムのシャットダウン
    """
    try
        log_info("システムシャットダウン開始")
        
        # APIサーバーの停止
        if is_server_running(8000)
            stop_api_server(8000)
            log_info("APIサーバーを停止しました")
        end
        
        # 接続プールのクリーンアップ
        cleanup_connection_pool()
        log_info("接続プールをクリーンアップしました")
        
        log_info("システムシャットダウン完了")
        println("システムが正常にシャットダウンされました")
        
    catch e
        log_error("シャットダウン中にエラーが発生しました", Dict("error" => string(e)))
        println("シャットダウン中にエラーが発生しました: $(string(e))")
    end
end

# システム情報表示
function system_info()
    """
    システム情報を表示
    """
    println("=== Julia在庫管理システム 情報 ===")
    
    # 接続プール統計
    pool_stats = get_pool_statistics()
    println("\n📊 データベース接続プール:")
    println("   総接続数: $(pool_stats[:total_connections])")
    println("   アクティブ: $(pool_stats[:active_connections])")
    println("   アイドル: $(pool_stats[:idle_connections])")
    println("   使用率: $(round(pool_stats[:usage_rate] * 100, digits=1))%")
    
    # ユーザー統計
    users = get_all_users()
    admin_count = count(user -> user.role == "admin", users)
    manager_count = count(user -> user.role == "manager", users)
    user_count = count(user -> user.role == "user", users)
    
    println("\n👥 ユーザー統計:")
    println("   管理者: $admin_count")
    println("   マネージャー: $manager_count")
    println("   一般ユーザー: $user_count")
    println("   総ユーザー数: $(length(users))")
    
    # 在庫統計
    try
        conn = get_connection_from_pool()
        try
            all_stocks = get_all_stocks(conn)
            out_of_stock = get_out_of_stock_items(conn)
            low_stock = get_low_stock_items(conn, 10)
            
            println("\n📦 在庫統計:")
            println("   総在庫アイテム数: $(length(all_stocks))")
            println("   在庫切れ: $(length(out_of_stock))")
            println("   低在庫 (10以下): $(length(low_stock))")
            
            if !isempty(all_stocks)
                total_value = sum(stock.price * stock.quantity for stock in all_stocks)
                println("   総在庫価値: ¥$(round(total_value, digits=2))")
            end
            
        finally
            return_connection_to_pool(conn)
        end
    catch e
        println("   在庫統計の取得中にエラーが発生しました: $(string(e))")
    end
    
    println("")
end

end
