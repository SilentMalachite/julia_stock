module ExcelHandler

using XLSX
using DataFrames
using Dates

include("../models/Stock.jl")
include("../database/DuckDBConnection.jl")

export export_to_excel, import_from_excel

"""
在庫データをExcelファイルにエクスポート
"""
function export_to_excel(filepath::String, data::Union{DataFrame, Nothing}=nothing)
    try
        # データが指定されていない場合は、データベースから全在庫を取得
        if isnothing(data)
            data = Stock.all()
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
                    "product_code" => get(row, :product_code, ""),
                    "product_name" => get(row, :product_name, ""),
                    "category" => get(row, :category, "その他"),
                    "quantity" => get(row, :quantity, 0),
                    "unit" => get(row, :unit, "個"),
                    "price" => get(row, :price, 0.0),
                    "location" => get(row, :location, ""),
                    "description" => get(row, :description, "")
                )
                
                # データベースに挿入
                Stock.create(stock_data)
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