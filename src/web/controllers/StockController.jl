module StockController

using HTTP
using JSON3
using DataFrames
using Dates
using Genie.Responses
using Genie.Renderers.Json

include("../../models/Stock.jl")
include("../../database/DuckDBConnection.jl")

"""
全在庫一覧を取得
"""
function index()
    try
        stocks = Stock.all()
        return json(stocks, status=200)
    catch e
        return json(Dict("error" => "在庫一覧の取得に失敗しました: $(e)"), status=500)
    end
end

"""
特定の在庫を取得
"""
function show(id::Int)
    try
        stock = Stock.find(id)
        return json(stock, status=200)
    catch e
        if occursin("not found", lowercase(string(e)))
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        else
            return json(Dict("error" => "在庫の取得に失敗しました: $(e)"), status=500)
        end
    end
end

"""
新規在庫を作成
"""
function create(payload::Dict)
    try
        # バリデーション
        if !haskey(payload, "product_code") || isempty(payload["product_code"])
            return json(Dict("error" => "商品コードは必須です"), status=400)
        end
        
        stock = Stock.create(payload)
        response_data = merge(stock, Dict("message" => "在庫が正常に作成されました"))
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
        stock = Stock.update(id, payload)
        response_data = merge(stock, Dict("message" => "在庫が正常に更新されました"))
        return json(response_data, status=200)
    catch e
        if occursin("not found", lowercase(string(e)))
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        else
            return json(Dict("error" => "在庫の更新に失敗しました: $(e)"), status=500)
        end
    end
end

"""
在庫を削除
"""
function destroy(id::Int)
    try
        Stock.delete(id)
        return json(Dict("message" => "在庫が正常に削除されました"), status=200)
    catch e
        if occursin("not found", lowercase(string(e)))
            return json(Dict("error" => "在庫が見つかりません"), status=404)
        else
            return json(Dict("error" => "在庫の削除に失敗しました: $(e)"), status=500)
        end
    end
end

end # module