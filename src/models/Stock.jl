module StockModel

using Dates

export Stock, add_quantity, reduce_quantity, filter_by_category, filter_out_of_stock, 
       filter_low_stock, calculate_total_value, calculate_category_stats

struct Stock
    id::Int64
    name::String
    code::String
    quantity::Int64
    unit::String
    price::Float64
    category::String
    location::String
    created_at::DateTime
    updated_at::DateTime
    
    function Stock(id, name, code, quantity, unit, price, category, location, created_at, updated_at)
        # バリデーション
        id > 0 || throw(ArgumentError("IDは正の整数である必要があります"))
        !isempty(name) || throw(ArgumentError("商品名は空にできません"))
        !isempty(code) || throw(ArgumentError("商品コードは空にできません"))
        quantity >= 0 || throw(ArgumentError("数量は非負である必要があります"))
        price >= 0.0 || throw(ArgumentError("価格は非負である必要があります"))
        
        new(id, name, code, quantity, unit, price, category, location, created_at, updated_at)
    end
end

function add_quantity(stock::Stock, additional_quantity::Int64)::Stock
    additional_quantity >= 0 || throw(ArgumentError("追加数量は非負である必要があります"))
    
    Stock(
        stock.id,
        stock.name,
        stock.code,
        stock.quantity + additional_quantity,
        stock.unit,
        stock.price,
        stock.category,
        stock.location,
        stock.created_at,
        now()
    )
end

function reduce_quantity(stock::Stock, reduction_quantity::Int64)::Stock
    reduction_quantity >= 0 || throw(ArgumentError("減少数量は非負である必要があります"))
    stock.quantity >= reduction_quantity || throw(ArgumentError("在庫不足です"))
    
    Stock(
        stock.id,
        stock.name,
        stock.code,
        stock.quantity - reduction_quantity,
        stock.unit,
        stock.price,
        stock.category,
        stock.location,
        stock.created_at,
        now()
    )
end

function filter_by_category(stocks::Vector{Stock}, category::String)::Vector{Stock}
    filter(stock -> stock.category == category, stocks)
end

function filter_out_of_stock(stocks::Vector{Stock})::Vector{Stock}
    filter(stock -> stock.quantity == 0, stocks)
end

function filter_low_stock(stocks::Vector{Stock}, threshold::Int64)::Vector{Stock}
    filter(stock -> stock.quantity < threshold, stocks)
end

function calculate_total_value(stocks::Vector{Stock})::Float64
    sum(stock -> stock.quantity * stock.price, stocks)
end

function calculate_category_stats(stocks::Vector{Stock})::Dict{String, Dict{Symbol, Any}}
    stats = Dict{String, Dict{Symbol, Any}}()
    
    for stock in stocks
        if !haskey(stats, stock.category)
            stats[stock.category] = Dict(
                :total_quantity => 0,
                :total_value => 0.0,
                :item_count => 0
            )
        end
        
        stats[stock.category][:total_quantity] += stock.quantity
        stats[stock.category][:total_value] += stock.quantity * stock.price
        stats[stock.category][:item_count] += 1
    end
    
    stats
end

end