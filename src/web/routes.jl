using Genie.Router
using Genie.Requests
using Genie.Responses
using JSON3
using ..AuthenticationSystem
using ..ErrorHandling
using Dates

# コントローラーをインクルード
include("controllers/StockController.jl")
include("controllers/ExcelController.jl")
include("controllers/ModernStockController.jl")

# APIルート定義

# 認証ヘルパー
function _bearer_token()
    h = headers()
    auth = get(h, "Authorization", get(h, "authorization", ""))
    if startswith(auth, "Bearer ")
        return auth[8:end]
    end
    return nothing
end

function _with_auth(permission::Union{Nothing,String}, f::Function)
    token = _bearer_token()
    user = verify_jwt_token(token === nothing ? "" : token)
    if user === nothing
        return json(Dict("error" => "Unauthorized"), status=401)
    end
    if permission !== nothing && !has_permission(user, String(permission))
        return json(Dict("error" => "Forbidden"), status=403)
    end
    return f(user)
end

# 簡易レート制限（IP x ルート）
const _RATE_STORE = Dict{Tuple{String,String}, Vector{Float64}}()

function _client_ip()
    h = headers()
    xff = get(h, "x-forwarded-for", get(h, "X-Forwarded-For", ""))
    if !isempty(xff)
        return split(xff, ",")[1] |> strip
    end
    xr = get(h, "X-Real-IP", get(h, "x-real-ip", ""))
    if !isempty(xr)
        return strip(xr)
    end
    return get(h, "Remote-Addr", get(h, "remote-addr", "unknown"))
end

function _rate_limit!(route_key::String; limit::Int=30, window::Int=60)
    ip = _client_ip()
    key = (ip, route_key)
    nowt = time()
    vec = get!(_RATE_STORE, key, Float64[])
    # 期限切れを掃除
    cutoff = nowt - window
    filter!(t -> t >= cutoff, vec)
    if length(vec) >= limit
        return true
    end
    push!(vec, nowt)
    return false
end

# 在庫管理API
route("/api/stocks", method = GET) do
    _with_auth("view_all_stocks") do user
        StockController.index()
    end
end

route("/api/stocks/:id::Int", method = GET) do
    _with_auth("view_all_stocks") do user
        StockController.show(payload(:id))
    end
end

route("/api/stocks", method = POST) do
    _with_auth("create_stock") do user
        if _rate_limit!("POST:/api/stocks"; limit=120, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_create_attempt", Dict("user"=>user.username))
        data = JSON3.read(String(rawpayload()), Dict{String, Any})
        resp = StockController.create(data)
        if resp.status == 201
            log_security_event("stock_created", Dict("user"=>user.username))
        end
        resp
    end
end

route("/api/stocks/:id::Int", method = PUT) do
    _with_auth("update_stock") do user
        if _rate_limit!("PUT:/api/stocks"; limit=240, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_update_attempt", Dict("user"=>user.username, "id"=>payload(:id)))
        data = JSON3.read(String(rawpayload()), Dict{String, Any})
        resp = StockController.update(payload(:id), data)
        if resp.status == 200
            log_security_event("stock_updated", Dict("user"=>user.username, "id"=>payload(:id)))
        end
        resp
    end
end

route("/api/stocks/:id::Int", method = DELETE) do
    _with_auth("delete_stock") do user
        if _rate_limit!("DELETE:/api/stocks"; limit=120, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_delete_attempt", Dict("user"=>user.username, "id"=>payload(:id)))
        resp = StockController.destroy(payload(:id))
        if resp.status == 200
            log_security_event("stock_deleted", Dict("user"=>user.username, "id"=>payload(:id)))
        end
        resp
    end
end

# Excel連携API
route("/api/excel/import", method = POST) do
    _with_auth("import_data") do user
        ExcelController.import_excel()
    end
end

route("/api/excel/export", method = GET) do
    _with_auth("export_data") do user
        ExcelController.export_excel()
    end
end

# ヘルスチェックエンドポイント
route("/api/health") do
    # ヘルスチェックは公開
    json(Dict("status" => "ok", "timestamp" => now()))
end

# 認証（公開）
route("/api/auth/login", method = POST) do
    if _rate_limit!("/api/auth/login"; limit=10, window=60)
        log_security_event("rate_limited", Dict("route"=>"/api/auth/login", "ip"=>_client_ip()))
        return json(Dict("error" => "Too Many Requests"), status=429)
    end
    data = JSON3.read(String(rawpayload()), Dict{String, Any})
    username = get(data, "username", "")
    password = get(data, "password", "")
    result = authenticate_user(String(username), String(password))
    if result === nothing
        log_security_event("login_failed", Dict("username"=>String(username), "ip"=>_client_ip()))
        return json(Dict("error" => "Invalid credentials"), status=401)
    end
    log_security_event("login_success", Dict("username"=>result.username, "ip"=>_client_ip()))
    return json(Dict(
        "username" => result.username,
        "role" => result.role,
        "token" => result.token,
        "expires_at" => result.expires_at
    ), status=200)
end

# モダンAPI エンドポイント
# ページネーション付き在庫一覧
route("/api/v2/stocks", method = GET) do
    _with_auth("view_all_stocks") do user
        ModernStockController.index_with_pagination()
    end
end

# バリデーション強化版の在庫作成
route("/api/v2/stocks", method = POST) do
    _with_auth("create_stock") do user
        if _rate_limit!("POST:/api/v2/stocks"; limit=120, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_create_attempt", Dict("user"=>user.username))
        data = JSON3.read(String(rawpayload()), Dict{String, Any})
        resp = ModernStockController.create_with_validation(data)
        if resp.status == 201
            log_security_event("stock_created", Dict("user"=>user.username))
        end
        resp
    end
end

# 在庫更新
route("/api/v2/stocks/:id::Int", method = PUT) do
    _with_auth("update_stock") do user
        if _rate_limit!("PUT:/api/v2/stocks"; limit=240, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_update_attempt", Dict("user"=>user.username, "id"=>payload(:id)))
        resp = ModernStockController.update_with_validation(payload(:id))
        if resp.status == 200
            log_security_event("stock_updated", Dict("user"=>user.username, "id"=>payload(:id)))
        end
        resp
    end
end

# 在庫削除
route("/api/v2/stocks/:id::Int", method = DELETE) do
    _with_auth("delete_stock") do user
        if _rate_limit!("DELETE:/api/v2/stocks"; limit=120, window=60)
            return json(Dict("error" => "Too Many Requests"), status=429)
        end
        log_security_event("stock_delete_attempt", Dict("user"=>user.username, "id"=>payload(:id)))
        resp = ModernStockController.destroy(payload(:id))
        if resp.status == 200
            log_security_event("stock_deleted", Dict("user"=>user.username, "id"=>payload(:id)))
        end
        resp
    end
end

# 一括更新
route("/api/v2/stocks/bulk-update", method = POST) do
    _with_auth("update_stock") do user
        ModernStockController.bulk_update()
    end
end

# 詳細統計情報
route("/api/v2/stocks/statistics", method = GET) do
    _with_auth("view_analytics") do user
        ModernStockController.detailed_statistics()
    end
end

# HTMLビューのルート
route("/") do
    serve_static_file("views/stocks/modern_index.jl.html")
end

route("/stocks/modern") do
    serve_static_file("views/stocks/modern_index.jl.html")
end
