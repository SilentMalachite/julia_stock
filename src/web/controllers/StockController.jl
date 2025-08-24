module StockController

using HTTP
using JSON3
using DataFrames
using Dates
using Genie.Responses
using Genie.Renderers.Json

include("../../models/Stock.jl")
include("../../database/ConnectionPool.jl")
include("../../database/DuckDBConnection.jl")

"""
全在庫一覧を取得
"""
function index()
    try
        conn = ConnectionPool.get_connection_from_pool()
        stocks = DuckDBConnection.get_all_stocks(conn)
        # レスポンス用に整形
        items = [
            Dict(
                :id => s.id,
                :product_code => s.code,
                :product_name => s.name,
                :category => s.category,
                :quantity => s.quantity,
                :unit => s.unit,
                :price => s.price,
                :location => s.location,
                :created_at => s.created_at,
                :updated_at => s.updated_at
            ) for s in stocks
        ]
        return json(items, status=200)
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
特定の在庫を取得
"""
function show(id::Int)
    try
        conn = ConnectionPool.get_connection_from_pool()
        s = DuckDBConnection.get_stock_by_id(conn, id)
        if s === nothing
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        end
        item = Dict(
            :id => s.id,
            :product_code => s.code,
            :product_name => s.name,
            :category => s.category,
            :quantity => s.quantity,
            :unit => s.unit,
            :price => s.price,
            :location => s.location,
            :created_at => s.created_at,
            :updated_at => s.updated_at
        )
        return json(item, status=200)
    catch e
        return json(Dict("error" => "在庫の取得に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
新規在庫を作成
"""
function create(payload::Dict)
    try
        # バリデーション
        if !haskey(payload, "product_code") || isempty(string(payload["product_code"]))
            return json(Dict("error" => "商品コードは必須です"), status=400)
        end

        # 型整形
        code = String(get(payload, "product_code", ""))
        name = String(get(payload, "product_name", ""))
        category = String(get(payload, "category", ""))
        unit = String(get(payload, "unit", ""))
        location = String(get(payload, "location", "N/A"))
        qv = get(payload, "quantity", 0)
        quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? 0 : tryparse(Int, qv)) : Int(qv)
        pv = get(payload, "price", 0)
        price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? 0.0 : tryparse(Float64, pv)) : Float64(pv)

        id = Int64(round(datetime2unix(now()) * 1000))
        nowdt = now()
        stock = StockModel.Stock(id, name, code, quantity, unit, price, category, location, nowdt, nowdt)

        conn = ConnectionPool.get_connection_from_pool()
        try
            DuckDBConnection.insert_stock(conn, stock)
        finally
            try
                ConnectionPool.return_connection_to_pool(conn)
            catch
            end
        end

        response_data = Dict(
            :id => stock.id,
            :product_code => stock.code,
            :product_name => stock.name,
            :category => stock.category,
            :quantity => stock.quantity,
            :unit => stock.unit,
            :price => stock.price,
            :location => stock.location,
            :created_at => stock.created_at,
            :updated_at => stock.updated_at,
            :message => "在庫が正常に作成されました"
        )
        return json(response_data, status=201)
    catch e
        return json(Dict("error" => "在庫の作成に失敗しました: $(e)"), status=500)
    end
end

"""
在庫を更新
"""
function update(id::Int, payload::Dict)
    try
        conn = ConnectionPool.get_connection_from_pool()
        s = DuckDBConnection.get_stock_by_id(conn, id)
        if s === nothing
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        end
        name = haskey(payload, "product_name") ? String(payload["product_name"]) : s.name
        code = haskey(payload, "product_code") ? String(payload["product_code"]) : s.code
        category = haskey(payload, "category") ? String(payload["category"]) : s.category
        unit = haskey(payload, "unit") ? String(payload["unit"]) : s.unit
        location = haskey(payload, "location") ? String(payload["location"]) : s.location
        qv = haskey(payload, "quantity") ? payload["quantity"] : s.quantity
        quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? s.quantity : tryparse(Int, qv)) : Int(qv)
        pv = haskey(payload, "price") ? payload["price"] : s.price
        price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? s.price : tryparse(Float64, pv)) : Float64(pv)
        updated = StockModel.Stock(s.id, name, code, quantity, unit, price, category, location, s.created_at, now())
        DuckDBConnection.update_stock(conn, updated)
        response_data = Dict(
            :id => updated.id,
            :product_code => updated.code,
            :product_name => updated.name,
            :category => updated.category,
            :quantity => updated.quantity,
            :unit => updated.unit,
            :price => updated.price,
            :location => updated.location,
            :updated_at => updated.updated_at,
            :message => "在庫が正常に更新されました"
        )
        return json(response_data, status=200)
    catch e
        return json(Dict("error" => "在庫の更新に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

"""
在庫を削除
"""
function destroy(id::Int)
    try
        conn = ConnectionPool.get_connection_from_pool()
        s = DuckDBConnection.get_stock_by_id(conn, id)
        if s === nothing
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        end
        DuckDBConnection.delete_stock(conn, id)
        return json(Dict("message" => "在庫が正常に削除されました"), status=200)
    catch e
        return json(Dict("error" => "在庫の削除に失敗しました: $(e)"), status=500)
    finally
        try
            ConnectionPool.return_connection_to_pool(conn)
        catch
        end
    end
end

end # module
