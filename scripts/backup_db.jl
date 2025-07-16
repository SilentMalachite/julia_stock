#!/usr/bin/env julia

using Dates
using DuckDB
using DataFrames
using JSON3
using Tar
using CodecZlib

# デフォルトのパス設定
const DEFAULT_DB_PATH = "data/inventory.duckdb"
const DEFAULT_BACKUP_DIR = "data/backups"

"""
データベースのバックアップを作成

Args:
    db_path: バックアップ元のデータベースパス
    backup_dir: バックアップ先ディレクトリ
    
Returns:
    作成されたバックアップファイルのパス
"""
function create_backup(db_path::String=DEFAULT_DB_PATH, backup_dir::String=DEFAULT_BACKUP_DIR)
    # バックアップディレクトリを作成
    mkpath(backup_dir)
    
    # タイムスタンプ付きバックアップファイル名を生成
    timestamp = Dates.format(now(), "yyyymmdd_HHMMSS")
    backup_filename = "backup_$(timestamp).duckdb"
    backup_path = joinpath(backup_dir, backup_filename)
    
    println("バックアップを開始します...")
    println("元のデータベース: $db_path")
    println("バックアップ先: $backup_path")
    
    try
        # ファイルをコピー（DuckDBは単一ファイルなので単純コピーでOK）
        cp(db_path, backup_path, force=true)
        
        # ファイルサイズを確認
        size_mb = round(filesize(backup_path) / 1024 / 1024, digits=2)
        println("バックアップが完了しました ($(size_mb) MB)")
        
        return backup_path
    catch e
        println("エラー: バックアップの作成に失敗しました - $e")
        rethrow(e)
    end
end

"""
圧縮されたバックアップを作成

Args:
    db_path: バックアップ元のデータベースパス
    backup_dir: バックアップ先ディレクトリ
    
Returns:
    作成された圧縮バックアップファイルのパス
"""
function create_compressed_backup(db_path::String=DEFAULT_DB_PATH, backup_dir::String=DEFAULT_BACKUP_DIR)
    # 通常のバックアップを作成
    backup_path = create_backup(db_path, backup_dir)
    
    # 圧縮ファイル名
    compressed_path = backup_path * ".tar.gz"
    
    println("バックアップを圧縮しています...")
    
    try
        # tar.gz形式で圧縮
        open(compressed_path, "w") do io
            gzio = GzipCompressorStream(io)
            Tar.create(backup_path, gzio)
            close(gzio)
        end
        
        # 元のバックアップファイルを削除
        rm(backup_path)
        
        # 圧縮率を計算
        original_size = filesize(db_path)
        compressed_size = filesize(compressed_path)
        compression_ratio = round(100 * (1 - compressed_size / original_size), digits=1)
        
        println("圧縮が完了しました (圧縮率: $(compression_ratio)%)")
        
        return compressed_path
    catch e
        println("エラー: 圧縮に失敗しました - $e")
        rethrow(e)
    end
end

"""
バックアップからリストア

Args:
    backup_path: リストア元のバックアップファイルパス
    restore_path: リストア先のデータベースパス
"""
function restore_backup(backup_path::String, restore_path::String=DEFAULT_DB_PATH)
    println("リストアを開始します...")
    println("バックアップ元: $backup_path")
    println("リストア先: $restore_path")
    
    # 既存のデータベースをバックアップ
    if isfile(restore_path)
        temp_backup = restore_path * ".temp_backup"
        cp(restore_path, temp_backup, force=true)
        println("既存のデータベースを一時バックアップしました: $temp_backup")
    end
    
    try
        # 圧縮ファイルの場合は解凍
        if endswith(backup_path, ".tar.gz")
            println("圧縮ファイルを解凍しています...")
            temp_dir = mktempdir()
            
            open(backup_path, "r") do io
                gzio = GzipDecompressorStream(io)
                Tar.extract(gzio, temp_dir)
                close(gzio)
            end
            
            # 解凍されたファイルを探す
            extracted_files = readdir(temp_dir)
            db_file = first(f -> endswith(f, ".duckdb"), extracted_files)
            actual_backup_path = joinpath(temp_dir, db_file)
            
            # リストア実行
            cp(actual_backup_path, restore_path, force=true)
            
            # 一時ディレクトリを削除
            rm(temp_dir, recursive=true)
        else
            # 通常のバックアップファイルをコピー
            cp(backup_path, restore_path, force=true)
        end
        
        println("リストアが完了しました")
        
        # 一時バックアップを削除
        if isfile(restore_path * ".temp_backup")
            rm(restore_path * ".temp_backup")
        end
    catch e
        println("エラー: リストアに失敗しました - $e")
        
        # エラー時は元のデータベースを復元
        if isfile(restore_path * ".temp_backup")
            cp(restore_path * ".temp_backup", restore_path, force=true)
            println("元のデータベースを復元しました")
        end
        
        rethrow(e)
    end
end

"""
バックアップファイルのリストを取得

Args:
    backup_dir: バックアップディレクトリ
    
Returns:
    バックアップファイルのパスのリスト（新しい順）
"""
function list_backups(backup_dir::String=DEFAULT_BACKUP_DIR)
    if !isdir(backup_dir)
        return String[]
    end
    
    # バックアップファイルを検索
    files = readdir(backup_dir, join=true)
    backup_files = filter(f -> occursin(r"backup_.*\.(duckdb|tar\.gz)$", f), files)
    
    # 更新日時でソート（新しい順）
    sort!(backup_files, by=f -> -mtime(f))
    
    return backup_files
end

"""
古いバックアップを削除

Args:
    backup_dir: バックアップディレクトリ
    keep_count: 保持するバックアップ数（デフォルト: 7）
"""
function cleanup_old_backups(backup_dir::String=DEFAULT_BACKUP_DIR; keep_count::Int=7)
    backups = list_backups(backup_dir)
    
    if length(backups) <= keep_count
        println("削除するバックアップはありません（現在: $(length(backups))個）")
        return
    end
    
    # 削除対象のバックアップ
    to_delete = backups[(keep_count+1):end]
    
    println("$(length(to_delete))個の古いバックアップを削除します...")
    
    for backup in to_delete
        try
            rm(backup)
            println("削除: $(basename(backup))")
        catch e
            println("警告: $(basename(backup)) の削除に失敗しました - $e")
        end
    end
    
    println("クリーンアップが完了しました")
end

"""
バックアップのメタデータを保存

Args:
    backup_path: バックアップファイルのパス
    metadata: メタデータの辞書
"""
function save_backup_metadata(backup_path::String, metadata::Dict)
    metadata_path = backup_path * ".meta.json"
    
    open(metadata_path, "w") do io
        JSON3.write(io, metadata)
    end
end

"""
バックアップのメタデータを読み込み

Args:
    backup_path: バックアップファイルのパス
    
Returns:
    メタデータの辞書
"""
function load_backup_metadata(backup_path::String)
    metadata_path = backup_path * ".meta.json"
    
    if !isfile(metadata_path)
        return Dict()
    end
    
    return JSON3.read(read(metadata_path, String), Dict)
end

"""
バックアップの状態を表示
"""
function show_backup_status(backup_dir::String=DEFAULT_BACKUP_DIR)
    println("\n=== バックアップ状態 ===")
    
    backups = list_backups(backup_dir)
    
    if isempty(backups)
        println("バックアップが見つかりません")
        return
    end
    
    println("バックアップ数: $(length(backups))")
    println("\n最新のバックアップ:")
    
    for (i, backup) in enumerate(backups[1:min(5, end)])
        size_mb = round(filesize(backup) / 1024 / 1024, digits=2)
        mtime_str = Dates.format(unix2datetime(mtime(backup)), "yyyy-mm-dd HH:MM:SS")
        
        # メタデータを読み込み
        metadata = load_backup_metadata(backup)
        meta_info = isempty(metadata) ? "" : " [メタデータあり]"
        
        println("  $i. $(basename(backup)) - $(size_mb) MB - $mtime_str$meta_info")
    end
    
    # ディスク使用量
    total_size = sum(filesize, backups) / 1024 / 1024
    println("\n合計サイズ: $(round(total_size, digits=2)) MB")
end

# メイン処理
if abspath(PROGRAM_FILE) == @__FILE__
    # コマンドライン引数を処理
    if length(ARGS) == 0
        # デフォルト動作：バックアップを作成
        backup_path = create_compressed_backup()
        
        # メタデータを保存
        metadata = Dict(
            "created_at" => now(),
            "julia_version" => VERSION,
            "host" => gethostname(),
            "database_size" => filesize(DEFAULT_DB_PATH)
        )
        save_backup_metadata(backup_path, metadata)
        
        # 古いバックアップをクリーンアップ
        cleanup_old_backups()
        
        # 状態を表示
        show_backup_status()
    elseif ARGS[1] == "list"
        # バックアップ一覧を表示
        show_backup_status()
    elseif ARGS[1] == "restore" && length(ARGS) >= 2
        # リストア実行
        restore_backup(ARGS[2])
    elseif ARGS[1] == "cleanup"
        # クリーンアップのみ実行
        keep_count = length(ARGS) >= 2 ? parse(Int, ARGS[2]) : 7
        cleanup_old_backups(keep_count=keep_count)
    else
        println("使用方法:")
        println("  julia backup_db.jl              # バックアップを作成")
        println("  julia backup_db.jl list         # バックアップ一覧を表示")
        println("  julia backup_db.jl restore PATH # 指定したバックアップからリストア")
        println("  julia backup_db.jl cleanup [N]  # 古いバックアップを削除（N個保持、デフォルト: 7）")
    end
end