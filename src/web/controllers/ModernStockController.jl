module ModernStockController

using HTTP
using JSON3
using DataFrames
using Dates
using Genie.Responses
using Genie.Renderers.Json
using Genie.Requests

include("../../models/Stock.jl")
include("../../database/DuckDBConnection.jl")
include("../../database/ConnectionPool.jl")
include("../../database/SecureDuckDBConnection.jl")
using DuckDB
using Random

"""
ページネーション付き在庫一覧を取得
"""
function index_with_pagination()
    try
        # リクエストパラメータの取得
        page = max(1, tryparse(Int, get(params(), :page, "1")) |> x -> x === nothing ? 1 : x)
        limit = clamp(tryparse(Int, get(params(), :limit, "20")) |> x -> x === nothing ? 20 : x, 1, 200)
        search = get(params(), :search, "")
        category = get(params(), :category, "")
        sort_by = lowercase(string(get(params(), :sortBy, "updated_at")))
        sort_order = lowercase(string(get(params(), :sortOrder, "desc")))
        
        # オフセットの計算
        offset = (page - 1) * limit

        # 接続はプールから取得
        conn = ConnectionPool.get_connection_from_pool()
        
        # WHERE句の構築
        where_parts = String[]
        qparams = Any[]
        if !isempty(search)
            push!(where_parts, "(name ILIKE ? OR code ILIKE ?)")
            push!(qparams, "%" * String(search) * "%")
            push!(qparams, "%" * String(search) * "%")
        end
        if !isempty(category)
            push!(where_parts, "category = ?")
            push!(qparams, String(category))
        end
        where_clause = isempty(where_parts) ? "" : "WHERE " * join(where_parts, " AND ")
        
        # 総件数の取得
        count_query = "SELECT COUNT(*) as total FROM stocks $where_clause"
        count_result = DuckDBConnection.execute_query(conn, count_query, qparams)
        total_count = count_result[1, :total]
        total_pages = ceil(Int, total_count / limit)
        
        # データの取得
        allowed_sort = Set(["updated_at","price","quantity","id","product_name","product_code","category"])
        sort_field = sort_by in allowed_sort ? sort_by : "updated_at"
        # フィールド名のマッピング（DB列名）
        sort_field_map = Dict(
            "product_name" => "name",
            "product_code" => "code"
        )
        sort_field_db = get(sort_field_map, sort_field, sort_field)
        sort_dir = sort_order in ["asc","desc"] ? sort_order : "desc"
        order_clause = "ORDER BY $(sort_field_db) $(sort_dir)"
        data_query = "SELECT id, code AS product_code, name AS product_name, quantity, unit, price, category, location, created_at, updated_at FROM stocks $where_clause $order_clause LIMIT ? OFFSET ?"
        qparams_data = copy(qparams)
        push!(qparams_data, limit)
        push!(qparams_data, offset)
        stocks_df = DuckDBConnection.execute_query(conn, data_query, qparams_data)
        
        # DataFrameを辞書の配列に変換
        stocks = [Dict(pairs(row)) for row in eachrow(stocks_df)]
        
        # 統計情報の取得
        statistics = get_statistics(conn, where_clause, qparams)
        
        # レスポンスの構築
        response_data = Dict(
            "stocks" => stocks,
            "currentPage" => page,
            "totalPages" => total_pages,
            "totalItems" => total_count,
            "statistics" => statistics
        )
        
        return json(response_data, status=200)
        
    catch e
        return json(Dict("error" => "在庫一覧の取得に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
ページネーション付き在庫一覧（テスト/直呼び出し用）
"""
function index_with_pagination(params_dict::Dict{String,Any})
    # パラメータ解釈
    page = max(1, tryparse(Int, get(params_dict, "page", 1)) |> x -> x === nothing ? 1 : x)
    limit = clamp(tryparse(Int, get(params_dict, "limit", 20)) |> x -> x === nothing ? 20 : x, 1, 200)
    search = String(get(params_dict, "search", ""))
    category = String(get(params_dict, "category", ""))
    sort_by = lowercase(string(get(params_dict, "sortBy", "updated_at")))
    sort_order = lowercase(string(get(params_dict, "sortOrder", "desc")))

    # 以降は既存ロジックを再利用
    try
        offset = (page - 1) * limit
        conn = ConnectionPool.get_connection_from_pool()
        where_parts = String[]
        qparams = Any[]
        if !isempty(search)
            push!(where_parts, "(name ILIKE ? OR code ILIKE ?)")
            push!(qparams, "%" * search * "%")
            push!(qparams, "%" * search * "%")
        end
        if !isempty(category)
            push!(where_parts, "category = ?")
            push!(qparams, category)
        end
        where_clause = isempty(where_parts) ? "" : "WHERE " * join(where_parts, " AND ")
        count_query = "SELECT COUNT(*) as total FROM stocks $where_clause"
        count_result = DuckDBConnection.execute_query(conn, count_query, qparams)
        total_count = count_result[1, :total]
        total_pages = ceil(Int, total_count / limit)
        allowed_sort = Set(["updated_at","price","quantity","id","product_name","product_code","category"])
        sort_field = sort_by in allowed_sort ? sort_by : "updated_at"
        sort_field_map = Dict("product_name"=>"name","product_code"=>"code")
        sort_field_db = get(sort_field_map, sort_field, sort_field)
        sort_dir = sort_order in ["asc","desc"] ? sort_order : "desc"
        order_clause = "ORDER BY $(sort_field_db) $(sort_dir)"
        data_query = "SELECT id, code AS product_code, name AS product_name, quantity, unit, price, category, location, created_at, updated_at FROM stocks $where_clause $order_clause LIMIT ? OFFSET ?"
        qparams_data = copy(qparams); push!(qparams_data, limit); push!(qparams_data, offset)
        stocks_df = DuckDBConnection.execute_query(conn, data_query, qparams_data)
        stocks = [Dict(pairs(row)) for row in eachrow(stocks_df)]
        statistics = get_statistics(conn, where_clause, qparams)
        response_data = Dict(
            "stocks" => stocks,
            "currentPage" => page,
            "totalPages" => total_pages,
            "totalItems" => total_count,
            "statistics" => statistics
        )
        return json(response_data, status=200)
    catch e
        return json(Dict("error" => "在庫一覧の取得に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
統計情報を取得
"""
function get_statistics(conn, where_clause::AbstractString="", qparams::AbstractVector=Any[])
    try
        # 総アイテム数と総額
        stats_query = """
            SELECT 
                COUNT(*) as total_items,
                SUM(quantity * price) as total_value,
                COUNT(CASE WHEN quantity = 0 THEN 1 END) as out_of_stock,
                COUNT(CASE WHEN quantity > 0 AND quantity < 10 THEN 1 END) as low_stock
            FROM stocks
            $where_clause
        """
        stats_result = DuckDBConnection.execute_query(conn, stats_query, qparams)
        
        # カテゴリ別の内訳
        category_query = """
            SELECT 
                category,
                COUNT(*) as count,
                SUM(quantity * price) as value
            FROM stocks
            $where_clause
            GROUP BY category
            ORDER BY count DESC
        """
        category_result = DuckDBConnection.execute_query(conn, category_query, qparams)
        category_breakdown = [Dict(pairs(row)) for row in eachrow(category_result)]
        
        return Dict(
            "totalItems" => stats_result[1, :total_items],
            "totalValue" => stats_result[1, :total_value] || 0,
            "outOfStockItems" => stats_result[1, :out_of_stock],
            "lowStockItems" => stats_result[1, :low_stock],
            "categoryBreakdown" => category_breakdown
        )
        
    catch e
        # エラーが発生した場合はデフォルト値を返す
        return Dict(
            "totalItems" => 0,
            "totalValue" => 0,
            "outOfStockItems" => 0,
            "lowStockItems" => 0,
            "categoryBreakdown" => []
        )
    end
end

"""
在庫作成（バリデーション強化版）
"""
function create_with_validation(payload::Dict)
    try
        # バリデーション
        validation_errors = validate_stock_data(payload)
        if !isempty(validation_errors)
            return json(Dict("error" => "バリデーションエラー", "details" => validation_errors), status=400)
        end
        
        # フィールド取り出しと型整形
        code = String(get(payload, "product_code", ""))
        name = String(get(payload, "product_name", ""))
        category = String(get(payload, "category", ""))
        unit = String(get(payload, "unit", ""))
        location = String(get(payload, "location", "N/A"))
        qv = get(payload, "quantity", 0)
        quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? 0 : tryparse(Int, qv)) : Int(qv)
        pv = get(payload, "price", 0)
        price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? 0.0 : tryparse(Float64, pv)) : Float64(pv)

        # ID生成（ミリ秒＋乱数）
        id = Int64(round(datetime2unix(now()) * 1000)) + rand(0:999)
        nowdt = now()

        # Stock構築
        stock = Stock(id, name, code, quantity, unit, price, category, location, nowdt, nowdt)

        # DB挿入（セキュア）
        conn = ConnectionPool.get_connection_from_pool()
        try
            SecureDuckDBConnection.secure_insert_stock(conn, stock)
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
        
        # 作成後の統計情報を含めて返す
        conn = ConnectionPool.get_connection_from_pool()
        statistics = get_statistics(conn)
        
        response_data = Dict(
            "id" => stock.id,
            "product_code" => stock.code,
            "product_name" => stock.name,
            "category" => stock.category,
            "quantity" => stock.quantity,
            "unit" => stock.unit,
            "price" => stock.price,
            "location" => stock.location,
            "created_at" => stock.created_at,
            "updated_at" => stock.updated_at,
            "message" => "在庫が正常に作成されました",
            "statistics" => statistics
        )
        
        return json(response_data, status=201)
        
    catch e
        return json(Dict("error" => "在庫の作成に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
在庫データのバリデーション
"""
function validate_stock_data(data::Dict)
    errors = Dict{String, String}()
    
    # 必須フィールドのチェック
    required_fields = ["product_code", "product_name", "category", "quantity", "unit", "price"]
    for field in required_fields
        if !haskey(data, field) || isempty(string(get(data, field, "")))
            errors[field] = "$(field)は必須です"
        end
    end
    
    # 数値フィールドの検証
    if haskey(data, "quantity")
        quantity = get(data, "quantity", 0)
        if isa(quantity, String)
            quantity = tryparse(Int, quantity)
        end
        if isnothing(quantity) || quantity < 0
            errors["quantity"] = "在庫数は0以上の整数である必要があります"
        end
    end
    
    if haskey(data, "price")
        price = get(data, "price", 0)
        if isa(price, String)
            price = tryparse(Float64, price)
        end
        if isnothing(price) || price < 0
            errors["price"] = "単価は0以上の数値である必要があります"
        end
    end
    
    # 商品コードの重複チェック
    if haskey(data, "product_code") && !isempty(get(data, "product_code", ""))
        conn = ConnectionPool.get_connection_from_pool()
        begin
            params = Any[data["product_code"]]
            check_query = "SELECT COUNT(*) as count FROM stocks WHERE code = ?"
            if haskey(data, "id")
                check_query *= " AND id != ?"
                push!(params, data["id"])
            end
            result = DuckDBConnection.execute_query(conn, check_query, params)
            if result[1, :count] > 0
                errors["product_code"] = "この商品コードは既に使用されています"
            end
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
    end
    
    return errors
end

"""
一括更新
"""
function bulk_update()
    try
        payload = JSON3.read(String(rawpayload()), Dict{String, Any})
        
        if !haskey(payload, "ids") || !haskey(payload, "updates")
            return json(Dict("error" => "idsとupdatesは必須です"), status=400)
        end
        
        ids = payload["ids"]
        updates = payload["updates"]
        # 型整形
        ids = [Int(x) for x in ids]

        updated_count = 0
        conn = ConnectionPool.get_connection_from_pool()
        try
            for id in ids
                try
                    existing = SecureDuckDBConnection.secure_get_stock_by_id(conn, id)
                    if existing === nothing
                        continue
                    end
                    name = haskey(updates, "product_name") ? String(updates["product_name"]) : existing.name
                    code = haskey(updates, "product_code") ? String(updates["product_code"]) : existing.code
                    category = haskey(updates, "category") ? String(updates["category"]) : existing.category
                    unit = haskey(updates, "unit") ? String(updates["unit"]) : existing.unit
                    location = haskey(updates, "location") ? String(updates["location"]) : existing.location
                    qval = haskey(updates, "quantity") ? updates["quantity"] : existing.quantity
                    quantity = isa(qval, String) ? (tryparse(Int, qval) === nothing ? existing.quantity : tryparse(Int, qval)) : Int(qval)
                    pval = haskey(updates, "price") ? updates["price"] : existing.price
                    price = isa(pval, String) ? (tryparse(Float64, pval) === nothing ? existing.price : tryparse(Float64, pval)) : Float64(pval)
                    updated = Stock(existing.id, name, code, quantity, unit, price,
                                    category, location, existing.created_at, now())
                    SecureDuckDBConnection.secure_update_stock(conn, updated)
                    updated_count += 1
                catch
                    # 個別のエラーはスキップ
                end
            end
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end

        return json(Dict(
            "message" => "$(updated_count)件の在庫を更新しました",
            "updated_count" => updated_count,
            "requested_count" => length(ids)
        ), status=200)
        
    catch e
        return json(Dict("error" => "一括更新に失敗しました: $(e)"), status=500)
    end
end

"""
一括更新（テスト/直呼び出し用）
"""
function bulk_update(payload::Dict{String,Any})
    try
        if !haskey(payload, "ids") || !haskey(payload, "updates")
            return json(Dict("error" => "idsとupdatesは必須です"), status=400)
        end
        ids = [Int(x) for x in payload["ids"]]
        updates = payload["updates"]
        updated_count = 0
        conn = ConnectionPool.get_connection_from_pool()
        try
            for id in ids
                try
                    existing = SecureDuckDBConnection.secure_get_stock_by_id(conn, id)
                    if existing === nothing
                        continue
                    end
                    name = haskey(updates, "product_name") ? String(updates["product_name"]) : existing.name
                    code = haskey(updates, "product_code") ? String(updates["product_code"]) : existing.code
                    category = haskey(updates, "category") ? String(updates["category"]) : existing.category
                    unit = haskey(updates, "unit") ? String(updates["unit"]) : existing.unit
                    location = haskey(updates, "location") ? String(updates["location"]) : existing.location
                    qval = haskey(updates, "quantity") ? updates["quantity"] : existing.quantity
                    quantity = isa(qval, String) ? (tryparse(Int, qval) === nothing ? existing.quantity : tryparse(Int, qval)) : Int(qval)
                    pval = haskey(updates, "price") ? updates["price"] : existing.price
                    price = isa(pval, String) ? (tryparse(Float64, pval) === nothing ? existing.price : tryparse(Float64, pval)) : Float64(pval)
                    updated = Stock(existing.id, name, code, quantity, unit, price,
                                    category, location, existing.created_at, now())
                    SecureDuckDBConnection.secure_update_stock(conn, updated)
                    updated_count += 1
                catch
                end
            end
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
        return json(Dict("updated_count"=>updated_count, "requested_count"=>length(ids)), status=200)
    catch e
        return json(Dict("error" => "一括更新に失敗しました: $(e)"), status=500)
    end
end

"""
詳細な統計情報を取得
"""
function detailed_statistics()
    try
        conn = ConnectionPool.get_connection_from_pool()
        
        # 基本統計
        basic_stats = get_statistics(conn)
        
        # 最近の活動
        recent_query = """
            SELECT 
                id,
                name AS product_name,
                'updated' as action,
                updated_at as timestamp
            FROM stocks
            ORDER BY updated_at DESC
            LIMIT 10
        """
        recent_df = DuckDBConnection.execute_query(conn, recent_query)
        recent_activity = [Dict(pairs(row)) for row in eachrow(recent_df)]
        
        # 在庫切れ警告リスト
        alerts_query = """
            SELECT 
                id,
                code AS product_code,
                name AS product_name,
                quantity,
                unit,
                CASE 
                    WHEN quantity = 0 THEN 'out_of_stock'
                    WHEN quantity < 10 THEN 'low_stock'
                END as alert_type
            FROM stocks
            WHERE quantity < 10
            ORDER BY quantity ASC, product_name ASC
        """
        alerts_df = DuckDBConnection.execute_query(conn, alerts_query)
        low_stock_alerts = [Dict(pairs(row)) for row in eachrow(alerts_df)]
        
        # 価格帯分布
        price_distribution_query = """
            SELECT 
                CASE 
                    WHEN price < 1000 THEN '0-999'
                    WHEN price < 5000 THEN '1000-4999'
                    WHEN price < 10000 THEN '5000-9999'
                    ELSE '10000+'
                END as price_range,
                COUNT(*) as count
            FROM stocks
            GROUP BY price_range
            ORDER BY 
                CASE price_range
                    WHEN '0-999' THEN 1
                    WHEN '1000-4999' THEN 2
                    WHEN '5000-9999' THEN 3
                    ELSE 4
                END
        """
        price_df = DuckDBConnection.execute_query(conn, price_distribution_query)
        price_distribution = [Dict(pairs(row)) for row in eachrow(price_df)]
        
        response_data = merge(basic_stats, Dict(
            "recentActivity" => recent_activity,
            "lowStockAlerts" => low_stock_alerts,
            "priceDistribution" => price_distribution,
            "lastUpdated" => now()
        ))
        
        return json(response_data, status=200)
        
    catch e
        return json(Dict("error" => "統計情報の取得に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
在庫更新（バリデーション + セキュア更新）
"""
function update_with_validation(id::Int)
    try
        updates = JSON3.read(String(rawpayload()), Dict{String, Any})

        conn = ConnectionPool.get_connection_from_pool()
        try
            existing = SecureDuckDBConnection.secure_get_stock_by_id(conn, id)
            if existing === nothing
                return json(Dict("error" => "在庫が見つかりません"), status=404)
            end

            name = haskey(updates, "product_name") ? String(updates["product_name"]) : existing.name
            code = haskey(updates, "product_code") ? String(updates["product_code"]) : existing.code
            category = haskey(updates, "category") ? String(updates["category"]) : existing.category
            unit = haskey(updates, "unit") ? String(updates["unit"]) : existing.unit
            location = haskey(updates, "location") ? String(updates["location"]) : existing.location

            quantity = existing.quantity
            if haskey(updates, "quantity")
                qv = updates["quantity"]
                quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? existing.quantity : tryparse(Int, qv)) : Int(qv)
            end

            price = existing.price
            if haskey(updates, "price")
                pv = updates["price"]
                price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? existing.price : tryparse(Float64, pv)) : Float64(pv)
            end

            updated_stock = Stock(existing.id, name, code, quantity, unit, price,
                                  category, location, existing.created_at, now())
            SecureDuckDBConnection.secure_update_stock(conn, updated_stock)

            response = Dict(
                "id" => updated_stock.id,
                "product_code" => updated_stock.code,
                "product_name" => updated_stock.name,
                "category" => updated_stock.category,
                "quantity" => updated_stock.quantity,
                "unit" => updated_stock.unit,
                "price" => updated_stock.price,
                "location" => updated_stock.location,
                "updated_at" => updated_stock.updated_at,
                "message" => "在庫が正常に更新されました"
            )
            return json(response, status=200)
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
    catch e
        return json(Dict("error" => "在庫の更新に失敗しました: $(e)"), status=500)
    end
end

"""
在庫更新（テスト/直呼び出し用）
"""
function update_with_validation(id::Int, updates::Dict{String,Any})
    try
        conn = ConnectionPool.get_connection_from_pool()
        try
            existing = SecureDuckDBConnection.secure_get_stock_by_id(conn, id)
            if existing === nothing
                return json(Dict("error" => "在庫が見つかりません"), status=404)
            end
            name = haskey(updates, "product_name") ? String(updates["product_name"]) : existing.name
            code = haskey(updates, "product_code") ? String(updates["product_code"]) : existing.code
            category = haskey(updates, "category") ? String(updates["category"]) : existing.category
            unit = haskey(updates, "unit") ? String(updates["unit"]) : existing.unit
            location = haskey(updates, "location") ? String(updates["location"]) : existing.location
            quantity = existing.quantity
            if haskey(updates, "quantity")
                qv = updates["quantity"]
                quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? existing.quantity : tryparse(Int, qv)) : Int(qv)
            end
            price = existing.price
            if haskey(updates, "price")
                pv = updates["price"]
                price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? existing.price : tryparse(Float64, pv)) : Float64(pv)
            end
            updated_stock = Stock(existing.id, name, code, quantity, unit, price,
                                  category, location, existing.created_at, now())
            SecureDuckDBConnection.secure_update_stock(conn, updated_stock)
            response = Dict(
                "id" => updated_stock.id,
                "product_code" => updated_stock.code,
                "product_name" => updated_stock.name,
                "category" => updated_stock.category,
                "quantity" => updated_stock.quantity,
                "unit" => updated_stock.unit,
                "price" => updated_stock.price,
                "location" => updated_stock.location,
                "updated_at" => updated_stock.updated_at,
                "message" => "在庫が正常に更新されました"
            )
            return json(response, status=200)
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
    catch e
        return json(Dict("error" => "在庫の更新に失敗しました: $(e)"), status=500)
    end
end

"""
在庫削除（セキュア削除）
"""
function destroy(id::Int)
    try
        conn = ConnectionPool.get_connection_from_pool()
        try
            existing = SecureDuckDBConnection.secure_get_stock_by_id(conn, id)
            if existing === nothing
                return json(Dict("error" => "在庫が見つかりません"), status=404)
            end
            SecureDuckDBConnection.secure_delete_stock(conn, id)
            return json(Dict("message" => "在庫が正常に削除されました"), status=200)
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end
    catch e
        return json(Dict("error" => "在庫の削除に失敗しました: $(e)"), status=500)
    end
end

end # module
