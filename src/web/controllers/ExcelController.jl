module ExcelController

using HTTP
using JSON3
using XLSX
using DataFrames
using Dates
using Genie.Responses
using Genie.Renderers.Json
using Genie.Requests

include("../../excel/ExcelHandler.jl")
include("../../models/Stock.jl")

"""
Excelファイルにエクスポート
"""
function export_excel()
    try
        # 一時ファイルパスを生成
        temp_file = tempname() * ".xlsx"
        
        # Excelファイルを生成
        ExcelHandler.export_to_excel(temp_file)
        
        # ファイルを読み込み
        file_content = read(temp_file)
        
        # ファイル名を生成
        filename = "inventory_export_$(Dates.format(now(), "yyyymmdd_HHMMSS")).xlsx"
        
        # レスポンスを作成
        response = HTTP.Response(200, file_content)
        HTTP.setheader(response, "Content-Type" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")
        HTTP.setheader(response, "Content-Disposition" => "attachment; filename=\"$filename\"")
        
        # 一時ファイルを削除
        rm(temp_file, force=true)
        
        return response
    catch e
        return json(Dict("error" => "Excelエクスポートに失敗しました: $(e)"), status=500)
    end
end

"""
Excelファイルからインポート
"""
function import_excel(file_path::String="")
    try
        # ファイルパスが指定されていない場合は、アップロードされたファイルを処理
        if isempty(file_path)
            # Genieのファイルアップロード処理
            if haskey(filespayload(), "file")
                uploaded_file = filespayload()["file"]
                file_path = uploaded_file.path
            else
                return json(Dict("error" => "ファイルがアップロードされていません"), status=400)
            end
        end
        
        # ファイルの存在確認
        if !isfile(file_path)
            return json(Dict("error" => "ファイルが見つかりません"), status=400)
        end
        
        # Excelファイルからインポート
        imported_count = ExcelHandler.import_from_excel(file_path)
        
        return json(Dict(
            "success" => true,
            "imported_count" => imported_count,
            "message" => "Excelファイルのインポートが完了しました"
        ), status=200)
    catch e
        return json(Dict("error" => "Excelインポートに失敗しました: $(e)"), status=400)
    end
end

end # module