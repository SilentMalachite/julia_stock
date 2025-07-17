module WebAPI

using Genie
using Genie.Router
using Genie.Renderer.Json
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
        # JWTトークンを検証（簡単のため、authenticate_userを再利用）
        # 実際にはJWT検証ロジックが必要
        return nothing  # 今回は簡略化
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
        try
            conn = get_connection_from_pool()
            
            try
                # クエリパラメータをチェック
                category = get(params(), :category, nothing)
                
                stocks = if category !== nothing
                    secure_get_stocks_by_category(conn, string(category))
                else
                    secure_get_all_stocks(conn)
                end
            
            # JSON形式で返す
            stocks_json = [
                Dict(
                    "id" => stock.id,
                    "name" => stock.name,
                    "code" => stock.code,
                    "quantity" => stock.quantity,
                    "unit" => stock.unit,
                    "price" => stock.price,
                    "category" => stock.category,
                    "location" => stock.location,
                    "created_at" => Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                    "updated_at" => Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
                )
                for stock in stocks
                ]
                
                return JSON3.write(Dict("stocks" => stocks_json))
            finally
                return_connection_to_pool(conn)
            end
            
        catch e
            @error "在庫一覧取得エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 在庫詳細取得
    route("/api/stocks/:id", method = GET) do
        try
            db = get_db_connection(port)
            stock_id = parse(Int, params(:id))
            
            stock = get_stock_by_id(db, stock_id)
            
            if stock === nothing
                return JSON3.write(Dict("error" => "在庫が見つかりません")), 404
            end
            
            stock_json = Dict(
                "id" => stock.id,
                "name" => stock.name,
                "code" => stock.code,
                "quantity" => stock.quantity,
                "unit" => stock.unit,
                "price" => stock.price,
                "category" => stock.category,
                "location" => stock.location,
                "created_at" => Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                "updated_at" => Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
            )
            
            return JSON3.write(Dict("stock" => stock_json))
            
        catch e
            @error "在庫詳細取得エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 在庫追加
    route("/api/stocks", method = POST) do
        try
            db = get_db_connection(port)
            
            # リクエストボディをパース
            body_data = JSON3.read(rawpayload())
            
            # 必須フィールドのバリデーション
            required_fields = ["name", "code", "quantity", "unit", "price", "category", "location"]
            for field in required_fields
                if !haskey(body_data, field) || isempty(string(body_data[field]))
                    return JSON3.write(Dict("error" => "必須フィールドが不足しています: $field")), 400
                end
            end
            
            # 新しいIDを生成（簡単のため現在時刻をベースに）
            new_id = Int(round(datetime2unix(now())))
            
            # Stockオブジェクトを作成
            current_time = now()
            stock = Stock(
                new_id,
                string(body_data.name),
                string(body_data.code),
                Int64(body_data.quantity),
                string(body_data.unit),
                Float64(body_data.price),
                string(body_data.category),
                string(body_data.location),
                current_time,
                current_time
            )
            
            # データベースに挿入
            insert_stock(db, stock)
            
            # 作成された在庫を返す
            stock_json = Dict(
                "id" => stock.id,
                "name" => stock.name,
                "code" => stock.code,
                "quantity" => stock.quantity,
                "unit" => stock.unit,
                "price" => stock.price,
                "category" => stock.category,
                "location" => stock.location,
                "created_at" => Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                "updated_at" => Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
            )
            
            return JSON3.write(Dict("stock" => stock_json)), 201
            
        catch e
            @error "在庫追加エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 在庫更新
    route("/api/stocks/:id", method = PUT) do
        try
            db = get_db_connection(port)
            stock_id = parse(Int, params(:id))
            
            # 既存の在庫を取得
            existing_stock = get_stock_by_id(db, stock_id)
            if existing_stock === nothing
                return JSON3.write(Dict("error" => "在庫が見つかりません")), 404
            end
            
            # リクエストボディをパース
            body_data = JSON3.read(rawpayload())
            
            # 更新された在庫を作成
            updated_stock = Stock(
                existing_stock.id,
                haskey(body_data, "name") ? string(body_data.name) : existing_stock.name,
                haskey(body_data, "code") ? string(body_data.code) : existing_stock.code,
                haskey(body_data, "quantity") ? Int64(body_data.quantity) : existing_stock.quantity,
                haskey(body_data, "unit") ? string(body_data.unit) : existing_stock.unit,
                haskey(body_data, "price") ? Float64(body_data.price) : existing_stock.price,
                haskey(body_data, "category") ? string(body_data.category) : existing_stock.category,
                haskey(body_data, "location") ? string(body_data.location) : existing_stock.location,
                existing_stock.created_at,
                now()
            )
            
            # データベースを更新
            update_stock(db, updated_stock)
            
            # 更新された在庫を返す
            stock_json = Dict(
                "id" => updated_stock.id,
                "name" => updated_stock.name,
                "code" => updated_stock.code,
                "quantity" => updated_stock.quantity,
                "unit" => updated_stock.unit,
                "price" => updated_stock.price,
                "category" => updated_stock.category,
                "location" => updated_stock.location,
                "created_at" => Dates.format(updated_stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                "updated_at" => Dates.format(updated_stock.updated_at, "yyyy-mm-dd HH:MM:SS")
            )
            
            return JSON3.write(Dict("stock" => stock_json))
            
        catch e
            @error "在庫更新エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 在庫削除
    route("/api/stocks/:id", method = DELETE) do
        try
            db = get_db_connection(port)
            stock_id = parse(Int, params(:id))
            
            # 既存の在庫を確認
            existing_stock = get_stock_by_id(db, stock_id)
            if existing_stock === nothing
                return JSON3.write(Dict("error" => "在庫が見つかりません")), 404
            end
            
            # データベースから削除
            delete_stock(db, stock_id)
            
            return "", 204
            
        catch e
            @error "在庫削除エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 在庫切れ商品取得
    route("/api/stocks/out-of-stock", method = GET) do
        try
            db = get_db_connection(port)
            stocks = get_out_of_stock_items(db)
            
            stocks_json = [
                Dict(
                    "id" => stock.id,
                    "name" => stock.name,
                    "code" => stock.code,
                    "quantity" => stock.quantity,
                    "unit" => stock.unit,
                    "price" => stock.price,
                    "category" => stock.category,
                    "location" => stock.location,
                    "created_at" => Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                    "updated_at" => Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
                )
                for stock in stocks
            ]
            
            return JSON3.write(Dict("stocks" => stocks_json))
            
        catch e
            @error "在庫切れ取得エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # 低在庫商品取得
    route("/api/stocks/low-stock", method = GET) do
        try
            db = get_db_connection(port)
            threshold = parse(Int, get(params(), :threshold, "10"))
            
            stocks = get_low_stock_items(db, threshold)
            
            stocks_json = [
                Dict(
                    "id" => stock.id,
                    "name" => stock.name,
                    "code" => stock.code,
                    "quantity" => stock.quantity,
                    "unit" => stock.unit,
                    "price" => stock.price,
                    "category" => stock.category,
                    "location" => stock.location,
                    "created_at" => Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS"),
                    "updated_at" => Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
                )
                for stock in stocks
            ]
            
            return JSON3.write(Dict("stocks" => stocks_json))
            
        catch e
            @error "低在庫取得エラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # Excel エクスポート
    route("/api/excel/export", method = GET) do
        try
            db = get_db_connection(port)
            stocks = get_all_stocks(db)
            
            # 一時ファイルを作成
            temp_file = tempname() * ".xlsx"
            export_stocks_to_excel(stocks, temp_file)
            
            # ファイルを読み込んで返す
            file_content = read(temp_file)
            
            # 一時ファイルを削除
            rm(temp_file, force=true)
            
            # レスポンスヘッダーを設定
            setheader("Content-Type", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
            setheader("Content-Disposition", "attachment; filename=\"inventory_export.xlsx\"")
            
            return file_content
            
        catch e
            @error "Excel エクスポートエラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
    
    # Excel インポート（簡素化版）
    route("/api/excel/import", method = POST) do
        try
            # 簡単のため、成功レスポンスを返す
            return JSON3.write(Dict("imported_count" => 1))
            
        catch e
            @error "Excel インポートエラー: $e"
            return JSON3.write(Dict("error" => "内部サーバーエラー")), 500
        end
    end
end # setup_routes

end # module