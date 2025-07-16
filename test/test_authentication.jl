using Test
using HTTP
using JSON3
using Dates
using Base64

# 必要な関数をインポート
using .InventorySystem: User, create_user, authenticate_user, delete_user, get_all_users,
                       change_password, is_account_locked, unlock_account, 
                       init_auth_database

@testset "Authentication and Authorization Tests" begin
    
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
    
    @testset "API認証テスト" begin
        start_api_server(8100)
        
        try
            # テスト用ユーザー作成
            user = create_user("apiuser", "ApiPass123!", "api@example.com", "admin")
            auth_result = authenticate_user("apiuser", "ApiPass123!")
            token = auth_result.token
            
            # テスト: 認証なしでのAPIアクセス（拒否されるべき）
            response_no_auth = HTTP.get("http://localhost:8100/api/stocks", status_exception=false)
            @test response_no_auth.status == 401
            
            # テスト: 無効なトークンでのAPIアクセス
            invalid_headers = ["Authorization" => "Bearer invalid_token"]
            response_invalid = HTTP.get("http://localhost:8100/api/stocks", headers=invalid_headers, status_exception=false)
            @test response_invalid.status == 401
            
            # テスト: 正しいトークンでのAPIアクセス
            valid_headers = ["Authorization" => "Bearer $token"]
            response_valid = HTTP.get("http://localhost:8100/api/stocks", headers=valid_headers)
            @test response_valid.status == 200
            
            # テスト: 権限不足での操作拒否
            user_user = create_user("limiteduser", "LimitedPass123!", "limited@example.com", "user")
            user_auth = authenticate_user("limiteduser", "LimitedPass123!")
            user_token = user_auth.token
            user_headers = ["Authorization" => "Bearer $user_token"]
            
            # 一般ユーザーは在庫作成不可
            new_stock_data = Dict(
                "name" => "新規商品",
                "code" => "NEW001",
                "quantity" => 50,
                "unit" => "個",
                "price" => 2000.0,
                "category" => "新規カテゴリ",
                "location" => "B-2-2"
            )
            
            response_forbidden = HTTP.post(
                "http://localhost:8100/api/stocks",
                headers=vcat(user_headers, ["Content-Type" => "application/json"]),
                body=JSON3.write(new_stock_data),
                status_exception=false
            )
            @test response_forbidden.status == 403
            
            # 後片付け
            delete_user("apiuser")
            delete_user("limiteduser")
            
        finally
            stop_api_server(8100)
        end
    end
    
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
    
    @testset "パスワードリセットテスト" begin
        # テスト用ユーザー作成
        user = create_user("resetuser", "ResetPass123!", "reset@example.com", "user")
        
        # テスト: パスワードリセットトークンの生成
        reset_token = generate_password_reset_token("resetuser")
        @test !isempty(reset_token)
        
        # テスト: 無効なユーザーでのリセットトークン生成エラー
        @test_throws Exception generate_password_reset_token("nonexistentuser")
        
        # テスト: パスワードリセットの実行
        new_password = "NewResetPass123!"
        @test_nowarn reset_password_with_token(reset_token, new_password)
        
        # テスト: 新しいパスワードでのログイン
        auth_result = authenticate_user("resetuser", new_password)
        @test auth_result !== nothing
        
        # テスト: 古いパスワードでのログイン失敗
        @test authenticate_user("resetuser", "ResetPass123!") === nothing
        
        # テスト: 使用済みトークンでの再リセット失敗
        @test_throws Exception reset_password_with_token(reset_token, "AnotherPass123!")
        
        # 後片付け
        delete_user("resetuser")
    end
end