module ExcelHandler

using XLSX
using DataFrames
using Dates
using ..StockModel

export create_empty_excel, export_stocks_to_excel, import_stocks_from_excel,
       create_stock_template, get_excel_headers, validate_excel_format

function create_empty_excel(filepath::String)
    """
    空のExcelファイルを作成する
    
    Args:
        filepath: 作成するExcelファイルのパス
    """
    try
        XLSX.openxlsx(filepath, mode="w") do xf
            sheet = xf[1]
            XLSX.rename!(sheet, "在庫データ")
        end
    catch e
        error("空のExcelファイル作成に失敗しました: $e")
    end
end

function export_stocks_to_excel(stocks::Vector{Stock}, filepath::String)
    """
    在庫データをExcelファイルにエクスポートする
    
    Args:
        stocks: 在庫データのベクター
        filepath: エクスポート先のExcelファイルパス
    """
    try
        XLSX.openxlsx(filepath, mode="w") do xf
            sheet = xf[1]
            XLSX.rename!(sheet, "在庫データ")
            
            # ヘッダー行を設定
            headers = ["ID", "商品名", "商品コード", "数量", "単位", "価格", "カテゴリ", "保管場所", "作成日時", "更新日時"]
            for (col, header) in enumerate(headers)
                sheet[1, col] = header
            end
            
            # データ行を設定
            for (row, stock) in enumerate(stocks)
                data_row = row + 1  # ヘッダー行の次から開始
                sheet[data_row, 1] = stock.id
                sheet[data_row, 2] = stock.name
                sheet[data_row, 3] = stock.code
                sheet[data_row, 4] = stock.quantity
                sheet[data_row, 5] = stock.unit
                sheet[data_row, 6] = stock.price
                sheet[data_row, 7] = stock.category
                sheet[data_row, 8] = stock.location
                sheet[data_row, 9] = Dates.format(stock.created_at, "yyyy-mm-dd HH:MM:SS")
                sheet[data_row, 10] = Dates.format(stock.updated_at, "yyyy-mm-dd HH:MM:SS")
            end
        end
    catch e
        error("Excelエクスポートに失敗しました: $e")
    end
end

function import_stocks_from_excel(filepath::String)::Vector{Stock}
    """
    Excelファイルから在庫データをインポートする
    
    Args:
        filepath: インポートするExcelファイルのパス
        
    Returns:
        Vector{Stock}: インポートされた在庫データのベクター
    """
    if !isfile(filepath)
        throw(ArgumentError("ファイルが存在しません: $filepath"))
    end
    
    try
        stocks = Stock[]
        
        XLSX.openxlsx(filepath, mode="r") do xf
            sheet = xf[1]
            
            # データの範囲を取得
            data_range = XLSX.get_dimension(sheet)
            
            # ヘッダー行をスキップして、データ行から読み込み
            if data_range.stop.row <= 1
                # データ行がない場合は空のベクターを返す
                return stocks
            end
            
            for row in 2:data_range.stop.row
                # 空行をスキップ
                if sheet[row, 1] === missing || sheet[row, 1] === nothing
                    continue
                end
                
                try
                    # 日時文字列をDateTimeに変換
                    created_at_str = string(sheet[row, 9])
                    updated_at_str = string(sheet[row, 10])
                    
                    created_at = DateTime(created_at_str, "yyyy-mm-dd HH:MM:SS")
                    updated_at = DateTime(updated_at_str, "yyyy-mm-dd HH:MM:SS")
                    
                    stock = Stock(
                        Int64(sheet[row, 1]),           # ID
                        string(sheet[row, 2]),          # 商品名
                        string(sheet[row, 3]),          # 商品コード
                        Int64(sheet[row, 4]),           # 数量
                        string(sheet[row, 5]),          # 単位
                        Float64(sheet[row, 6]),         # 価格
                        string(sheet[row, 7]),          # カテゴリ
                        string(sheet[row, 8]),          # 保管場所
                        created_at,                     # 作成日時
                        updated_at                      # 更新日時
                    )
                    
                    push!(stocks, stock)
                catch e
                    @warn "行 $row の読み込みでエラーが発生しました: $e"
                    continue
                end
            end
        end
        
        return stocks
    catch e
        error("Excelインポートに失敗しました: $e")
    end
end

function create_stock_template(filepath::String)
    """
    在庫データ入力用のテンプレートExcelファイルを作成する
    
    Args:
        filepath: テンプレートファイルのパス
    """
    try
        XLSX.openxlsx(filepath, mode="w") do xf
            sheet = xf[1]
            XLSX.rename!(sheet, "在庫データテンプレート")
            
            # ヘッダー行を設定
            headers = ["ID", "商品名", "商品コード", "数量", "単位", "価格", "カテゴリ", "保管場所", "作成日時", "更新日時"]
            for (col, header) in enumerate(headers)
                sheet[1, col] = header
            end
            
            # サンプル行を追加
            sample_time = Dates.format(now(), "yyyy-mm-dd HH:MM:SS")
            sheet[2, 1] = 1
            sheet[2, 2] = "サンプル商品"
            sheet[2, 3] = "SAMPLE001"
            sheet[2, 4] = 100
            sheet[2, 5] = "個"
            sheet[2, 6] = 1000.0
            sheet[2, 7] = "サンプルカテゴリ"
            sheet[2, 8] = "A-1-1"
            sheet[2, 9] = sample_time
            sheet[2, 10] = sample_time
        end
    catch e
        error("テンプレート作成に失敗しました: $e")
    end
end

function get_excel_headers(filepath::String)::Vector{String}
    """
    Excelファイルのヘッダー行を取得する
    
    Args:
        filepath: Excelファイルのパス
        
    Returns:
        Vector{String}: ヘッダーのベクター
    """
    if !isfile(filepath)
        throw(ArgumentError("ファイルが存在しません: $filepath"))
    end
    
    try
        headers = String[]
        
        XLSX.openxlsx(filepath, mode="r") do xf
            sheet = xf[1]
            data_range = XLSX.get_dimension(sheet)
            
            for col in 1:data_range.stop.column
                header_value = sheet[1, col]
                if header_value !== missing && header_value !== nothing
                    push!(headers, string(header_value))
                end
            end
        end
        
        return headers
    catch e
        error("ヘッダー取得に失敗しました: $e")
    end
end

function validate_excel_format(filepath::String)::Bool
    """
    Excelファイルのフォーマットが正しいかチェックする
    
    Args:
        filepath: チェックするExcelファイルのパス
        
    Returns:
        Bool: フォーマットが正しい場合はtrue
    """
    if !isfile(filepath)
        return false
    end
    
    try
        headers = get_excel_headers(filepath)
        expected_headers = ["ID", "商品名", "商品コード", "数量", "単位", "価格", "カテゴリ", "保管場所", "作成日時", "更新日時"]
        
        # ヘッダーの数をチェック
        if length(headers) != length(expected_headers)
            return false
        end
        
        # 各ヘッダーの存在をチェック
        for expected_header in expected_headers
            if !(expected_header in headers)
                return false
            end
        end
        
        # データ行の存在をチェック（最低1行のデータが必要）
        XLSX.openxlsx(filepath, mode="r") do xf
            sheet = xf[1]
            data_range = XLSX.get_dimension(sheet)
            
            # ヘッダー行のみの場合は無効
            if data_range.stop.row <= 1
                return false
            end
        end
        
        return true
    catch e
        @warn "フォーマット検証中にエラーが発生しました: $e"
        return false
    end
end

end