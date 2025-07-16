#!/usr/bin/env julia

# データベース初期化スクリプト

using Pkg
Pkg.activate(".")

include("../src/InventorySystem.jl")
using .InventorySystem

function main()
    println("データベースを初期化中...")
    
    try
        # データベース接続
        db = db_connect("data/inventory.db")
        
        # テーブル作成
        create_stock_table(db)
        println("✓ 在庫テーブルを作成しました")
        
        # サンプルデータの挿入
        sample_stocks = [
            Stock(1, "ノートパソコン", "PC001", 50, "台", 80000.0, "電子機器", "A-1-1", now(), now()),
            Stock(2, "マウス", "MS001", 100, "個", 2000.0, "電子機器", "A-1-2", now(), now()),
            Stock(3, "キーボード", "KB001", 75, "個", 5000.0, "電子機器", "A-1-3", now(), now()),
            Stock(4, "プリンター用紙", "PP001", 200, "パック", 500.0, "オフィス用品", "B-1-1", now(), now()),
            Stock(5, "ボールペン", "BP001", 500, "本", 100.0, "オフィス用品", "B-1-2", now(), now()),
            Stock(6, "コピー用紙", "CP001", 0, "パック", 300.0, "オフィス用品", "B-1-3", now(), now()),
            Stock(7, "デスクチェア", "DC001", 25, "脚", 15000.0, "家具", "C-1-1", now(), now()),
            Stock(8, "デスク", "DK001", 30, "台", 25000.0, "家具", "C-1-2", now(), now()),
            Stock(9, "書棚", "BS001", 15, "台", 12000.0, "家具", "C-2-1", now(), now()),
            Stock(10, "スマートフォン", "SP001", 5, "台", 60000.0, "電子機器", "A-2-1", now(), now())
        ]
        
        for stock in sample_stocks
            insert_stock(db, stock)
        end
        
        println("✓ サンプルデータ（$(length(sample_stocks))件）を挿入しました")
        
        # 統計情報を表示
        all_stocks = get_all_stocks(db)
        total_value = calculate_total_value(all_stocks)
        out_of_stock = get_out_of_stock_items(db)
        low_stock = get_low_stock_items(db, 20)
        
        println("\n📊 データベース統計:")
        println("   総在庫数: $(length(all_stocks))件")
        println("   総在庫価値: ¥$(Int(total_value))")
        println("   在庫切れ商品: $(length(out_of_stock))件")
        println("   低在庫商品 (20未満): $(length(low_stock))件")
        
        # データベース接続を閉じる
        db_close(db)
        
        println("\n✅ データベースの初期化が完了しました!")
        
    catch e
        println("❌ エラーが発生しました: $e")
        exit(1)
    end
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end