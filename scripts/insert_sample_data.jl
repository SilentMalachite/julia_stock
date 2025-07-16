#!/usr/bin/env julia

# サンプルデータ挿入スクリプト

using Pkg
Pkg.activate(".")

include("../src/InventorySystem.jl")
using .InventorySystem

function main()
    println("サンプルデータを挿入中...")
    
    try
        # データベース接続
        db = db_connect("data/inventory.db")
        
        # 追加のサンプルデータ
        additional_stocks = [
            Stock(11, "液晶モニター", "LM001", 30, "台", 25000.0, "電子機器", "A-2-2", now(), now()),
            Stock(12, "外付けHDD", "HDD001", 40, "台", 8000.0, "電子機器", "A-2-3", now(), now()),
            Stock(13, "ホワイトボード", "WB001", 10, "枚", 3000.0, "オフィス用品", "B-2-1", now(), now()),
            Stock(14, "会議テーブル", "MT001", 8, "台", 40000.0, "家具", "C-2-2", now(), now()),
            Stock(15, "スピーカー", "SP002", 20, "台", 15000.0, "電子機器", "A-3-1", now(), now()),
            Stock(16, "プロジェクター", "PJ001", 5, "台", 100000.0, "電子機器", "A-3-2", now(), now()),
            Stock(17, "ファイル", "FL001", 200, "個", 200.0, "オフィス用品", "B-2-2", now(), now()),
            Stock(18, "クリップボード", "CB001", 50, "個", 800.0, "オフィス用品", "B-2-3", now(), now()),
            Stock(19, "パーティション", "PT001", 12, "枚", 8000.0, "家具", "C-3-1", now(), now()),
            Stock(20, "タブレット", "TB001", 15, "台", 45000.0, "電子機器", "A-3-3", now(), now())
        ]
        
        for stock in additional_stocks
            insert_stock(db, stock)
        end
        
        println("✓ 追加サンプルデータ（$(length(additional_stocks))件）を挿入しました")
        
        # カテゴリ別統計
        all_stocks = get_all_stocks(db)
        category_stats = calculate_category_stats(all_stocks)
        
        println("\n📈 カテゴリ別統計:")
        for (category, stats) in category_stats
            println("   $category: $(stats[:item_count])品目, 総数量=$(stats[:total_quantity]), 総価値=¥$(Int(stats[:total_value]))")
        end
        
        # データベース接続を閉じる
        db_close(db)
        
        println("\n✅ サンプルデータの挿入が完了しました!")
        
    catch e
        println("❌ エラーが発生しました: $e")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end