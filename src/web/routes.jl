using Genie.Router
using Genie.Requests
using Genie.Responses
using JSON3

# コントローラーをインクルード
include("controllers/StockController.jl")
include("controllers/ExcelController.jl")
include("controllers/ModernStockController.jl")

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

# モダンAPI エンドポイント
# ページネーション付き在庫一覧
route("/api/v2/stocks", method = GET) do
    ModernStockController.index_with_pagination()
end

# バリデーション強化版の在庫作成
route("/api/v2/stocks", method = POST) do
    data = JSON3.read(String(rawpayload()), Dict{String, Any})
    ModernStockController.create_with_validation(data)
end

# 一括更新
route("/api/v2/stocks/bulk-update", method = POST) do
    ModernStockController.bulk_update()
end

# 詳細統計情報
route("/api/v2/stocks/statistics", method = GET) do
    ModernStockController.detailed_statistics()
end

# HTMLビューのルート
route("/") do
    serve_static_file("views/stocks/modern_index.jl.html")
end

route("/stocks/modern") do
    serve_static_file("views/stocks/modern_index.jl.html")
end