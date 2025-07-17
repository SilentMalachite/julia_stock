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

"""
ページネーション付き在庫一覧を取得
"""
function index_with_pagination()
    try
        # リクエストパラメータの取得
        page = parse(Int, get(params(), :page, "1"))
        limit = parse(Int, get(params(), :limit, "20"))
        search = get(params(), :search, "")
        category = get(params(), :category, "")
        sort_by = get(params(), :sortBy, "updated_at")
        sort_order = get(params(), :sortOrder, "desc")
        
        # オフセットの計算
        offset = (page - 1) * limit
        
        # 基本クエリの構築
        conn = DuckDBConnection.get_connection()
        
        # WHERE句の構築
        where_clauses = String[]
        
        if !isempty(search)
            push!(where_clauses, "(product_name ILIKE '%$search%' OR product_code ILIKE '%$search%')")
        end
        
        if !isempty(category)
            push!(where_clauses, "category = '$category'")
        end
        
        where_clause = isempty(where_clauses) ? "" : "WHERE " * join(where_clauses, " AND ")
        
        # 総件数の取得
        count_query = "SELECT COUNT(*) as total FROM stocks $where_clause"
        count_result = DuckDBConnection.execute_query(conn, count_query)
        total_count = count_result[1, :total]
        total_pages = ceil(Int, total_count / limit)
        
        # データの取得
        order_clause = "ORDER BY $sort_by $sort_order"
        data_query = """
            SELECT * FROM stocks 
            $where_clause
            $order_clause
            LIMIT $limit OFFSET $offset
        """
        
        stocks_df = DuckDBConnection.execute_query(conn, data_query)
        
        # DataFrameを辞書の配列に変換
        stocks = [Dict(pairs(row)) for row in eachrow(stocks_df)]
        
        # 統計情報の取得
        statistics = get_statistics(conn, where_clause)
        
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
    end
end

"""
統計情報を取得
"""
function get_statistics(conn, where_clause="")
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
        
        stats_result = DuckDBConnection.execute_query(conn, stats_query)
        
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
        
        category_result = DuckDBConnection.execute_query(conn, category_query)
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
        
        # 在庫作成
        stock = Stock.create(payload)
        
        # 作成後の統計情報を含めて返す
        conn = DuckDBConnection.get_connection()
        statistics = get_statistics(conn)
        
        response_data = Dict(
            "id" => stock["id"],
            "product_code" => stock["product_code"],
            "product_name" => stock["product_name"],
            "category" => stock["category"],
            "quantity" => stock["quantity"],
            "unit" => stock["unit"],
            "price" => stock["price"],
            "location" => get(stock, "location", nothing),
            "description" => get(stock, "description", nothing),
            "created_at" => stock["created_at"],
            "updated_at" => stock["updated_at"],
            "message" => "在庫が正常に作成されました",
            "statistics" => statistics
        )
        
        return json(response_data, status=201)
        
    catch e
        return json(Dict("error" => "在庫の作成に失敗しました: $(e)"), status=500)
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
        conn = DuckDBConnection.get_connection()
        check_query = "SELECT COUNT(*) as count FROM stocks WHERE product_code = '$(data["product_code"])'"
        
        # 更新の場合はIDを除外
        if haskey(data, "id")
            check_query *= " AND id != $(data["id"])"
        end
        
        result = DuckDBConnection.execute_query(conn, check_query)
        if result[1, :count] > 0
            errors["product_code"] = "この商品コードは既に使用されています"
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
        
        # 各IDに対して更新を実行
        updated_count = 0
        for id in ids
            try
                Stock.update(id, updates)
                updated_count += 1
            catch
                # 個別のエラーは無視して続行
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
詳細な統計情報を取得
"""
function detailed_statistics()
    try
        conn = DuckDBConnection.get_connection()
        
        # 基本統計
        basic_stats = get_statistics(conn)
        
        # 最近の活動
        recent_query = """
            SELECT 
                id,
                product_name,
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
                product_code,
                product_name,
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
    end
end

end # module