using Genie.Router
using Genie.Requests
using Genie.Responses
using JSON3

# コントローラーをインクルード
include("controllers/StockController.jl")
include("controllers/ExcelController.jl")

# APIルート定義

# 在庫管理API
route("/api/stocks", method = GET) do
    StockController.index()
end

route("/api/stocks/:id::Int", method = GET) do
    StockController.show(payload(:id))
end

route("/api/stocks", method = POST) do
    data = JSON3.read(String(rawpayload()), Dict{String, Any})
    StockController.create(data)
end

route("/api/stocks/:id::Int", method = PUT) do
    data = JSON3.read(String(rawpayload()), Dict{String, Any})
    StockController.update(payload(:id), data)
end

route("/api/stocks/:id::Int", method = DELETE) do
    StockController.destroy(payload(:id))
end

# Excel連携API
route("/api/excel/import", method = POST) do
    ExcelController.import_excel()
end

route("/api/excel/export", method = GET) do
    ExcelController.export_excel()
end

# ヘルスチェックエンドポイント
route("/api/health") do
    json(Dict("status" => "ok", "timestamp" => now()))
end