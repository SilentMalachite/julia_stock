using Test
using Dates
using Base64

# 必要な関数をインポート
using .InventorySystem: User, create_user, authenticate_user, delete_user, get_all_users,
                       change_password, is_account_locked, unlock_account, 
                       init_auth_database, generate_jwt_token, verify_jwt_token, has_permission

@testset "Authentication and Authorization Tests" begin
    # JWTシークレットを設定
    ENV["JWT_SECRET"] = "testsecret_for_jwt_123456!"
    
    @testset "ユーザー登録テスト" begin
        # テスト: 正常なユーザー登録
        user_data = Dict(
            "username" => "testuser",
            "password" => "SecurePass123!",
            "email" => "test@example.com",
            "role" => "user"
        )
        
        @test_nowarn begin
            user = create_user(user_data["username"], user_data["password"], user_data["email"], user_data["role"])
            @test user.username == "testuser"
            @test user.email == "test@example.com"
            @test user.role == "user"
            @test user.password_hash != user_data["password"]  # パスワードがハッシュ化されている
        end
        
        # テスト: 重複ユーザー名での登録エラー
        @test_throws Exception create_user("testuser", "AnotherPass123!", "another@example.com", "user")
        
        # テスト: 不正なパスワードでの登録エラー
        weak_passwords = ["123", "password", "abc", ""]
        for weak_pass in weak_passwords
            @test_throws Exception create_user("user_$weak_pass", weak_pass, "user@example.com", "user")
        end
        
        # テスト: 不正なメールアドレスでの登録エラー
        invalid_emails = ["notanemail", "@example.com", "user@", "user space@example.com"]
        for invalid_email in invalid_emails
            @test_throws Exception create_user("user_email", "ValidPass123!", invalid_email, "user")
        end
        
        # 後片付け
        delete_user("testuser")
    end
    
    @testset "パスワードハッシュ化テスト" begin
        password = "TestPassword123!"
        
        # テスト: パスワードのハッシュ化
        hash1 = hash_password(password)
        hash2 = hash_password(password)
        
        @test hash1 != password  # 元のパスワードと異なる
        @test hash1 != hash2     # 同じパスワードでも異なるハッシュ（ソルト使用）
        @test length(hash1) > 20 # ハッシュが十分な長さ
        
        # テスト: パスワード検証
        @test verify_password(password, hash1) == true
        @test verify_password(password, hash2) == true
        @test verify_password("wrongpassword", hash1) == false
        @test verify_password("", hash1) == false
    end
    
    @testset "JWTトークン生成・検証テスト" begin
        # テスト用ユーザー
        user = create_user("tokenuser", "TokenPass123!", "token@example.com", "admin")
        
        # テスト: JWTトークンの生成
        token = generate_jwt_token(user)
        @test !isempty(token)
        @test length(split(token, '.')) == 3  # JWT形式（header.payload.signature）
        
        # テスト: JWTトークンの検証
        decoded_user = verify_jwt_token(token)
        @test decoded_user !== nothing
        @test decoded_user.username == "tokenuser"
        @test decoded_user.role == "admin"
        
        # テスト: 無効なトークンの検証
        invalid_tokens = [
            "invalid.token.here",
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.invalid.signature",
            "",
            "not.a.jwt"
        ]
        
        for invalid_token in invalid_tokens
            @test verify_jwt_token(invalid_token) === nothing
        end
        
        # テスト: 期限切れトークンのシミュレーション
        expired_token = generate_jwt_token(user, expires_in = -3600)  # 1時間前に期限切れ
        @test verify_jwt_token(expired_token) === nothing
        
        # 後片付け
        delete_user("tokenuser")
    end
    
    @testset "ユーザー認証テスト" begin
        # テスト用ユーザー作成
        create_user("authuser", "AuthPass123!", "auth@example.com", "user")
        
        # テスト: 正常な認証
        auth_result = authenticate_user("authuser", "AuthPass123!")
        @test auth_result !== nothing
        @test auth_result.username == "authuser"
        @test haskey(auth_result, :token)
        @test !isempty(auth_result.token)
        
        # テスト: 不正なパスワードでの認証失敗
        @test authenticate_user("authuser", "wrongpassword") === nothing
        
        # テスト: 存在しないユーザーでの認証失敗
        @test authenticate_user("nonexistentuser", "password") === nothing
        
        # テスト: 空の認証情報での失敗
        @test authenticate_user("", "") === nothing
        @test authenticate_user("authuser", "") === nothing
        @test authenticate_user("", "AuthPass123!") === nothing
        
        # 後片付け
        delete_user("authuser")
    end
    
    @testset "権限管理テスト" begin
        # 異なる権限のユーザーを作成
        admin_user = create_user("admin", "AdminPass123!", "admin@example.com", "admin")
        manager_user = create_user("manager", "ManagerPass123!", "manager@example.com", "manager")
        user_user = create_user("user", "UserPass123!", "user@example.com", "user")
        
        # テスト: 管理者権限の確認
        @test has_permission(admin_user, "create_stock") == true
        @test has_permission(admin_user, "update_stock") == true
        @test has_permission(admin_user, "delete_stock") == true
        @test has_permission(admin_user, "view_all_stocks") == true
        @test has_permission(admin_user, "manage_users") == true
        
        # テスト: マネージャー権限の確認
        @test has_permission(manager_user, "create_stock") == true
        @test has_permission(manager_user, "update_stock") == true
        @test has_permission(manager_user, "delete_stock") == true
        @test has_permission(manager_user, "view_all_stocks") == true
        @test has_permission(manager_user, "manage_users") == false
        
        # テスト: 一般ユーザー権限の確認
        @test has_permission(user_user, "create_stock") == false
        @test has_permission(user_user, "update_stock") == false
        @test has_permission(user_user, "delete_stock") == false
        @test has_permission(user_user, "view_all_stocks") == true
        @test has_permission(user_user, "manage_users") == false
        
        # テスト: 無効な権限名
        @test has_permission(admin_user, "invalid_permission") == false
        
        # 後片付け
        delete_user("admin")
        delete_user("manager")
        delete_user("user")
    end
    
    # APIサーバー依存のテストは現仕様では行わない（JWT/RBACは別テストにて検証）
    
    @testset "セッション管理テスト" begin
        # テスト用ユーザー作成
        user = create_user("sessionuser", "SessionPass123!", "session@example.com", "user")
        
        # テスト: セッション作成
        session = create_session(user)
        @test session !== nothing
        @test !isempty(session.session_id)
        @test session.user_id == user.id
        @test session.expires_at > now()
        
        # テスト: セッション検証
        retrieved_user = get_user_by_session(session.session_id)
        @test retrieved_user !== nothing
        @test retrieved_user.username == "sessionuser"
        
        # テスト: セッション無効化
        invalidate_session(session.session_id)
        @test get_user_by_session(session.session_id) === nothing
        
        # テスト: 期限切れセッション
        expired_session = create_session(user, expires_in = -3600)  # 1時間前に期限切れ
        @test get_user_by_session(expired_session.session_id) === nothing
        
        # 後片付け
        delete_user("sessionuser")
    end
    
    @testset "ブルートフォース攻撃対策テスト" begin
        # テスト用ユーザー作成
        create_user("bruteuser", "BrutePass123!", "brute@example.com", "user")
        
        # テスト: 連続ログイン失敗の検出
        failed_attempts = 0
        max_attempts = 5
        
        for i in 1:max_attempts + 1
            result = authenticate_user("bruteuser", "wrongpassword")
            if result === nothing
                failed_attempts += 1
            end
        end
        
        @test failed_attempts == max_attempts + 1
        
        # テスト: アカウントロック状態の確認
        @test is_account_locked("bruteuser") == true
        
        # テスト: ロック中の正しいパスワードでもログイン不可
        @test authenticate_user("bruteuser", "BrutePass123!") === nothing
        
        # テスト: アカウントロック解除
        unlock_account("bruteuser")
        @test is_account_locked("bruteuser") == false
        
        # テスト: ロック解除後の正常ログイン
        auth_result = authenticate_user("bruteuser", "BrutePass123!")
        @test auth_result !== nothing
        
        # 後片付け
        delete_user("bruteuser")
    end
    
    # パスワードリセットは現仕様で未実装のため除外
end
