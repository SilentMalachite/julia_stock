module ExcelHandler

using XLSX
using DataFrames
using Dates

include("../models/Stock.jl")
include("../database/DuckDBConnection.jl")
include("../database/ConnectionPool.jl")
include("../database/SecureDuckDBConnection.jl")

export export_to_excel, import_from_excel

"""
在庫データをExcelファイルにエクスポート
"""
function export_to_excel(filepath::String, data::Union{DataFrame, Nothing}=nothing)
    try
        # データが指定されていない場合は、データベースから全在庫を取得
        if isnothing(data)
            conn = ConnectionPool.get_connection_from_pool()
            try
                stocks = SecureDuckDBConnection.secure_get_all_stocks(conn)
                data = DataFrame(
                    id = [s.id for s in stocks],
                    product_code = [s.code for s in stocks],
                    product_name = [s.name for s in stocks],
                    category = [s.category for s in stocks],
                    quantity = [s.quantity for s in stocks],
                    unit = [s.unit for s in stocks],
                    price = [s.price for s in stocks],
                    location = [s.location for s in stocks],
                    created_at = [s.created_at for s in stocks],
                    updated_at = [s.updated_at for s in stocks]
                )
            finally
                try
                    ConnectionPool.return_connection_to_pool(conn)
                catch
                end
            end
        end
        
        # DataFrameが空の場合の処理
        if nrow(data) == 0
            @warn "エクスポートするデータがありません"
        end
        
        # Excelファイルに書き込み
        XLSX.writetable(filepath, 
            "在庫データ" => data,
            overwrite=true
        )
        
        return true
        
    catch e
        error("Excelエクスポートに失敗しました: $e")
    end
end

"""
Excelファイルから在庫データをインポート
"""
function import_from_excel(filepath::String)
    if !isfile(filepath)
        throw(ArgumentError("ファイルが存在しません: $filepath"))
    end
    
    try
        # Excelファイルを読み込み
        xf = XLSX.readxlsx(filepath)
        sheet_names = XLSX.sheetnames(xf)
        
        # 最初のシートを使用
        sheet = xf[sheet_names[1]]
        
        # データをDataFrameに変換
        df = DataFrame(XLSX.gettable(sheet)...)
        
        # カラム名の正規化（必要に応じて）
        rename!(df, 
            :商品コード => :product_code,
            :商品名 => :product_name,
            :カテゴリ => :category,
            :在庫数 => :quantity,
            :単位 => :unit,
            :単価 => :price,
            :保管場所 => :location,
            :備考 => :description
        )
        
        # 各行をデータベースに挿入
        imported_count = 0
        for row in eachrow(df)
            try
                stock_data = Dict(
                    "product_code" => _getrow(row, :product_code, ""),
                    "product_name" => _getrow(row, :product_name, ""),
                    "category" => _getrow(row, :category, "その他"),
                    "quantity" => _getrow(row, :quantity, 0),
                    "unit" => _getrow(row, :unit, "個"),
                    "price" => _getrow(row, :price, 0.0),
                    "location" => _getrow(row, :location, "")
                )
                # 保存
                code = String(get(stock_data, "product_code", ""))
                name = String(get(stock_data, "product_name", ""))
                category = String(get(stock_data, "category", "その他"))
                unit = String(get(stock_data, "unit", "個"))
                location = String(get(stock_data, "location", ""))
                qv = get(stock_data, "quantity", 0)
                quantity = isa(qv, String) ? (tryparse(Int, qv) === nothing ? 0 : tryparse(Int, qv)) : Int(qv)
                pv = get(stock_data, "price", 0.0)
                price = isa(pv, String) ? (tryparse(Float64, pv) === nothing ? 0.0 : tryparse(Float64, pv)) : Float64(pv)
                nowdt = now()
                id = Int64(round(datetime2unix(now()) * 1000))
                stock = StockModel.Stock(id, name, code, quantity, unit, price, category, location, nowdt, nowdt)
                conn = ConnectionPool.get_connection_from_pool()
                try
                    SecureDuckDBConnection.secure_insert_stock(conn, stock)
                finally
                    try
                        ConnectionPool.return_connection_to_pool(conn)
                    catch
                    end
                end
                imported_count += 1
                
            catch e
                @warn "行のインポートに失敗しました: $e"
                continue
            end
        end
        
        XLSX.close(xf)
        return imported_count
        
    catch e
        error("Excelインポートに失敗しました: $e")
    end
end

# DataFrameRow 安全取得
function _getrow(row, col::Symbol, default)
    namesyms = propertynames(row)
    if col in namesyms
        val = row[col]
        return val === missing ? default : val
    else
        return default
    end
end

"""
インポート用のテンプレートExcelファイルを作成
"""
function create_template(filepath::String)
    try
        # テンプレートデータ
        template_data = DataFrame(
            商品コード = ["SAMPLE-001", "SAMPLE-002"],
            商品名 = ["サンプル商品1", "サンプル商品2"],
            カテゴリ = ["電子部品", "機械部品"],
            在庫数 = [100, 50],
            単位 = ["個", "箱"],
            単価 = [1500.0, 3000.0],
            保管場所 = ["A-1-1", "B-2-3"],
            備考 = ["サンプルデータです", "インポート用テンプレート"]
        )
        
        # Excelファイルに書き込み
        XLSX.writetable(filepath,
            "インポートテンプレート" => template_data,
            overwrite=true
        )
        
        return true
        
    catch e
        error("テンプレート作成に失敗しました: $e")
    end
end

end # module
