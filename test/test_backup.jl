using Test
using Dates
using DuckDB

include("../scripts/backup_db.jl")

@testset "Database Backup Tests" begin
    # テスト用のデータベースとバックアップディレクトリ
    test_db_path = "data/test_backup.duckdb"
    backup_dir = "data/backups/test"
    
    # テスト用データベースを作成
    conn = DBInterface.connect(DuckDB.DB, test_db_path)
    DBInterface.execute(conn, """
        CREATE TABLE test_table (
            id INTEGER PRIMARY KEY,
            name VARCHAR,
            created_at TIMESTAMP
        )
    """)
    
    # テストデータを挿入
    DBInterface.execute(conn, """
        INSERT INTO test_table (id, name, created_at) 
        VALUES (1, 'Test Item', CURRENT_TIMESTAMP)
    """)
    DBInterface.close(conn)
    
    @testset "バックアップの作成" begin
        # バックアップを実行
        backup_path = create_backup(test_db_path, backup_dir)
        
        # バックアップファイルが作成されたか確認
        @test isfile(backup_path)
        @test filesize(backup_path) > 0
        
        # バックアップファイル名の形式を確認
        @test occursin("backup_", basename(backup_path))
        @test occursin(".duckdb", basename(backup_path))
    end
    
    @testset "バックアップのリストア" begin
        # バックアップを作成
        backup_path = create_backup(test_db_path, backup_dir)
        
        # 元のデータベースを削除
        rm(test_db_path, force=true)
        @test !isfile(test_db_path)
        
        # リストアを実行
        restore_backup(backup_path, test_db_path)
        
        # リストアされたか確認
        @test isfile(test_db_path)
        
        # データが復元されたか確認
        conn = DBInterface.connect(DuckDB.DB, test_db_path)
        result = DBInterface.execute(conn, "SELECT * FROM test_table WHERE id = 1")
        data = DataFrame(result)
        @test nrow(data) == 1
        @test data.name[1] == "Test Item"
        DBInterface.close(conn)
    end
    
    @testset "古いバックアップの削除" begin
        # 複数のバックアップを作成
        for i in 1:5
            create_backup(test_db_path, backup_dir)
            sleep(0.1)  # タイムスタンプが異なるようにする
        end
        
        # バックアップ数を確認
        backups = list_backups(backup_dir)
        @test length(backups) >= 5
        
        # 古いバックアップを削除（最新3つを残す）
        cleanup_old_backups(backup_dir, keep_count=3)
        
        # 残ったバックアップ数を確認
        remaining_backups = list_backups(backup_dir)
        @test length(remaining_backups) == 3
    end
    
    @testset "バックアップの圧縮" begin
        # 圧縮バックアップを作成
        compressed_backup = create_compressed_backup(test_db_path, backup_dir)
        
        # 圧縮ファイルが作成されたか確認
        @test isfile(compressed_backup)
        @test occursin(".tar.gz", compressed_backup)
        
        # 圧縮ファイルのサイズが元より小さいか確認
        original_size = filesize(test_db_path)
        compressed_size = filesize(compressed_backup)
        @test compressed_size < original_size * 0.9  # 少なくとも10%は圧縮される想定
    end
    
    @testset "バックアップのメタデータ" begin
        # バックアップを作成
        backup_path = create_backup(test_db_path, backup_dir)
        
        # メタデータを保存
        metadata = Dict(
            "created_at" => now(),
            "database_version" => "1.0.0",
            "table_count" => 1,
            "total_rows" => 1
        )
        save_backup_metadata(backup_path, metadata)
        
        # メタデータを読み込み
        loaded_metadata = load_backup_metadata(backup_path)
        @test loaded_metadata["database_version"] == "1.0.0"
        @test loaded_metadata["table_count"] == 1
    end
    
    # クリーンアップ
    rm(test_db_path, force=true)
    rm(backup_dir, force=true, recursive=true)
end