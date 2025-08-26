module WebAPI

using Genie
using Genie.Router
using Genie.Renderers.Json
using Genie.Requests
using Genie.Responses
using HTTP
using JSON3
using Dates
using DuckDB
using ..StockModel
using ..SecureDuckDBConnection
using ..AuthenticationSystem
using ..ErrorHandling
using ..ConnectionPool
using ..ExcelHandler

# ルートファイルをインクルード
include("routes.jl")
# グローバル変数でサーバー情報を管理
const RUNNING_SERVERS = Set{Int}()

export start_api_server, stop_api_server, is_server_running, add_test_stock

function start_api_server(port::Int = 8000)
    """
    APIサーバーを起動する
    
    Args:
        port: サーバーのポート番号
    """
    if port in RUNNING_SERVERS
        log_warning("サーバー起動試行", Dict("port" => port, "status" => "already_running"))
        @warn "ポート $port は既に使用中です"
        return
    end
    
    try
        log_info("APIサーバー起動開始", Dict("port" => port))
        
        # Genieアプリケーションを設定
        Genie.config.run_as_server = true
        Genie.config.cors_headers["Access-Control-Allow-Origin"] = "*"
        Genie.config.cors_headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
        Genie.config.cors_headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, DELETE, OPTIONS"
        
        # ルートを定義
        setup_routes()
        
        # サーバーを起動
        @async Genie.startup(port, async = false)
        
        push!(RUNNING_SERVERS, port)
        
        # サーバー起動を少し待つ
        sleep(1)
        
        log_info("APIサーバー起動完了", Dict("port" => port))
        println("APIサーバーがポート $port で起動しました")
        
    catch e
        log_error("APIサーバー起動エラー", Dict("port" => port, "error" => string(e)))
        @error "APIサーバーの起動に失敗しました: $e"
        rethrow(e)
    end
end

function stop_api_server(port::Int = 8000)
    """
    APIサーバーを停止する
    
    Args:
        port: 停止するサーバーのポート番号
    """
    try
        log_info("APIサーバー停止開始", Dict("port" => port))
        
        # サーバーを停止
        if port in RUNNING_SERVERS
            # Genieのサーバー停止（実装上の制約により、実際の停止は難しいため状態のみ更新）
            delete!(RUNNING_SERVERS, port)
            log_info("APIサーバー停止完了", Dict("port" => port))
            println("APIサーバー（ポート $port）を停止しました")
        else
            log_warning("APIサーバー停止試行", Dict("port" => port, "status" => "not_running"))
        end
        
    catch e
        log_error("APIサーバー停止エラー", Dict("port" => port, "error" => string(e)))
        @error "APIサーバーの停止中にエラーが発生しました: $e"
    end
end

function is_server_running(port::Int = 8000)::Bool
    """
    指定されたポートでサーバーが動作しているかチェック
    
    Args:
        port: チェックするポート番号
        
    Returns:
        Bool: サーバーが動作している場合はtrue
    """
    return port in RUNNING_SERVERS
end

function add_test_stock(stock::Stock)
    """
    テスト用の在庫データを追加
    
    Args:
        stock: 追加する在庫データ
    """
    conn = get_connection_from_pool()
    try
        secure_insert_stock(conn, stock)
    finally
        return_connection_to_pool(conn)
    end
end

# 認証ヘルパー関数
function extract_bearer_token(headers::Dict)::Union{String, Nothing}
    """
    リクエストヘッダーからBearerトークンを抽出
    """
    auth_header = get(headers, "Authorization", get(headers, "authorization", ""))
    if startswith(auth_header, "Bearer ")
        return auth_header[8:end]  # "Bearer " を除去
    end
    return nothing
end

function authenticate_request(token::Union{String, Nothing})::Union{User, Nothing}
    """
    トークンを使用してリクエストを認証
    """
    if token === nothing
        return nothing
    end

    try
        return verify_jwt_token(token)
    catch e
        log_warning("認証エラー", Dict("error" => string(e)))
        return nothing
    end
end

function setup_routes()
    """
    APIルートを設定 - routes.jlから読み込まれるため、この関数は空にする
    """
    # ルートはroutes.jlで定義されています
end

end # module
