module ErrorHandling

using Dates
using JSON3
using Logging

export init_logging, log_info, log_warning, log_error, log_debug,
       log_event, log_security_event, cleanup_old_logs,
       handle_database_error, handle_api_error, create_error_response,
       sanitize_log_data, mask_sensitive_data

# ログレベル定義
@enum LogLevel begin
    DEBUG = 1
    INFO = 2
    WARNING = 3
    ERROR = 4
    SECURITY = 5
end

# ログ設定
const LOG_CONFIG = Dict(
    :max_file_size => 10 * 1024 * 1024,  # 10MB
    :max_files => 5,
    :date_format => "yyyy-mm-dd HH:MM:SS",
    :log_level => INFO
)

# 機密データのパターン
const SENSITIVE_PATTERNS = [
    r"password\s*[:=]\s*['\"]?([^'\"\\s]+)" => "password: ***",
    r"token\s*[:=]\s*['\"]?([^'\"\\s]+)" => "token: ***",
    r"key\s*[:=]\s*['\"]?([^'\"\\s]+)" => "key: ***",
    r"secret\s*[:=]\s*['\"]?([^'\"\\s]+)" => "secret: ***",
    r"(\d{4}[-\s]?\d{4}[-\s]?\d{4}[-\s]?\d{4})" => "****-****-****-****",  # クレジットカード
    r"(\d{3}-\d{2}-\d{4})" => "***-**-****",  # SSN
    r"([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})" => "***@***.***"  # Email
]

function init_logging()
    """
    ログシステムを初期化
    """
    try
        # ログディレクトリの作成
        mkpath("logs")
        
        # 各種ログファイルの初期化
        init_log_file("logs/app.log")
        init_log_file("logs/error.log")
        init_log_file("logs/security.log")
        init_log_file("logs/debug.log")
        
        # グローバルログレベルの設定
        global_logger(FileLogger("logs/app.log"))
        
        log_info("ログシステムが初期化されました")
        
    catch e
        println("ログシステムの初期化に失敗: $e")
    end
end

function init_log_file(filepath::String)
    """
    ログファイルを初期化
    """
    if !isfile(filepath)
        open(filepath, "w") do io
            write(io, "# ログファイル開始: $(now())\n")
        end
    end
end

function format_timestamp()::String
    """
    タイムスタンプをフォーマット
    """
    return Dates.format(now(), LOG_CONFIG[:date_format])
end

function write_log(level::LogLevel, message::String, data::Dict = Dict(), log_file::String = "logs/app.log")
    """
    ログを書き込み
    """
    try
        timestamp = format_timestamp()
        level_str = string(level)
        
        # ログエントリの構築
        log_entry = Dict(
            "timestamp" => timestamp,
            "level" => level_str,
            "message" => message
        )
        
        # 追加データがある場合は含める
        if !isempty(data)
            sanitized_data = sanitize_log_data(data)
            log_entry["data"] = sanitized_data
        end
        
        # JSONフォーマットでログ出力
        log_line = JSON3.write(log_entry)
        
        # ファイルローテーションのチェック
        if should_rotate_log(log_file)
            rotate_log_file(log_file)
        end
        
        # ログファイルに書き込み
        open(log_file, "a") do io
            println(io, log_line)
        end
        
        # コンソール出力（デバッグモード時）
        if LOG_CONFIG[:log_level] <= DEBUG
            println("[$level_str] $timestamp: $message")
        end
        
    catch e
        # ログ出力でエラーが発生した場合はコンソールに出力
        println("ログ出力エラー: $e")
        println("元のメッセージ: $message")
    end
end

function sanitize_log_data(data::Dict)::Dict
    """
    ログデータから機密情報を除去
    """
    sanitized = Dict()
    
    for (key, value) in data
        if value isa String
            sanitized[key] = mask_sensitive_data(value)
        elseif value isa Dict
            sanitized[key] = sanitize_log_data(value)
        else
            # 機密的なキー名のチェック
            key_lower = lowercase(string(key))
            if any(contains(key_lower, sensitive) for sensitive in ["password", "token", "key", "secret"])
                sanitized[key] = "***"
            else
                sanitized[key] = value
            end
        end
    end
    
    return sanitized
end

function mask_sensitive_data(text::String)::String
    """
    文字列内の機密データをマスク
    """
    masked_text = text
    
    for (pattern, replacement) in SENSITIVE_PATTERNS
        masked_text = replace(masked_text, pattern => replacement)
    end
    
    return masked_text
end

function should_rotate_log(log_file::String)::Bool
    """
    ログファイルのローテーションが必要かチェック
    """
    try
        if isfile(log_file)
            file_size = stat(log_file).size
            return file_size > LOG_CONFIG[:max_file_size]
        end
    catch
        return false
    end
    
    return false
end

function rotate_log_file(log_file::String)
    """
    ログファイルをローテーション
    """
    try
        base_name = splitext(log_file)[1]
        extension = splitext(log_file)[2]
        
        # 既存のローテーションファイルをシフト
        for i in (LOG_CONFIG[:max_files]-1):-1:1
            old_file = "$(base_name).$(i)$(extension)"
            new_file = "$(base_name).$(i+1)$(extension)"
            
            if isfile(old_file)
                if i == LOG_CONFIG[:max_files]-1
                    rm(old_file)  # 最古のファイルを削除
                else
                    mv(old_file, new_file)
                end
            end
        end
        
        # 現在のファイルを .1 にリネーム
        if isfile(log_file)
            mv(log_file, "$(base_name).1$(extension)")
        end
        
    catch e
        println("ログローテーションエラー: $e")
    end
end

function log_info(message::String, data::Dict = Dict())
    """
    情報ログを出力
    """
    write_log(INFO, message, data, "logs/app.log")
end

function log_warning(message::String, data::Dict = Dict())
    """
    警告ログを出力
    """
    write_log(WARNING, message, data, "logs/app.log")
end

function log_error(message::String, data::Dict = Dict())
    """
    エラーログを出力
    """
    write_log(ERROR, message, data, "logs/error.log")
    write_log(ERROR, message, data, "logs/app.log")  # アプリログにも記録
end

function log_debug(message::String, data::Dict = Dict())
    """
    デバッグログを出力
    """
    if LOG_CONFIG[:log_level] <= DEBUG
        write_log(DEBUG, message, data, "logs/debug.log")
    end
end

function log_event(event_type::String, data::Dict = Dict())
    """
    イベントログを出力
    """
    log_data = merge(data, Dict("event_type" => event_type))
    write_log(INFO, "Event: $event_type", log_data, "logs/app.log")
end

function log_security_event(event_type::String, data::Dict = Dict())
    """
    セキュリティイベントログを出力
    """
    log_data = merge(data, Dict(
        "event_type" => event_type,
        "severity" => "security"
    ))
    write_log(SECURITY, "Security Event: $event_type", log_data, "logs/security.log")
    write_log(SECURITY, "Security Event: $event_type", log_data, "logs/app.log")
end

function cleanup_old_logs(days::Int = 30)
    """
    古いログファイルをクリーンアップ
    """
    try
        cutoff_date = now() - Day(days)
        log_dir = "logs"
        
        if isdir(log_dir)
            for file in readdir(log_dir)
                file_path = joinpath(log_dir, file)
                if isfile(file_path)
                    file_mod_time = unix2datetime(stat(file_path).mtime)
                    if file_mod_time < cutoff_date
                        rm(file_path)
                        log_info("古いログファイルを削除しました", Dict("file" => file_path))
                    end
                end
            end
        end
        
    catch e
        log_error("ログクリーンアップでエラーが発生しました", Dict("error" => string(e)))
    end
end

function handle_database_error(e::Exception, operation::String = "database operation")::String
    """
    データベースエラーを処理
    """
    error_id = generate_error_id()
    
    error_data = Dict(
        "error_id" => error_id,
        "operation" => operation,
        "error_type" => string(typeof(e)),
        "error_message" => string(e)
    )
    
    log_error("データベースエラーが発生しました", error_data)
    
    # ユーザー向けのエラーメッセージ（詳細な情報は含めない）
    return "データベース操作中にエラーが発生しました。エラーID: $error_id"
end

function handle_api_error(e::Exception, endpoint::String = "unknown", request_data::Dict = Dict())::Dict
    """
    APIエラーを処理してレスポンスを生成
    """
    error_id = generate_error_id()
    
    error_data = Dict(
        "error_id" => error_id,
        "endpoint" => endpoint,
        "error_type" => string(typeof(e)),
        "error_message" => string(e),
        "request_data" => sanitize_log_data(request_data)
    )
    
    log_error("APIエラーが発生しました", error_data)
    
    # エラーの種類に応じてHTTPステータスコードを決定
    status_code = if e isa ArgumentError
        400  # Bad Request
    elseif e isa BoundsError || e isa KeyError
        404  # Not Found
    elseif e isa MethodError
        405  # Method Not Allowed
    else
        500  # Internal Server Error
    end
    
    return create_error_response(status_code, "エラーが発生しました", error_id)
end

function create_error_response(status_code::Int, message::String, error_id::String = "")::Dict
    """
    標準化されたエラーレスポンスを作成
    """
    response = Dict(
        "error" => true,
        "status" => status_code,
        "message" => message,
        "timestamp" => now()
    )
    
    if !isempty(error_id)
        response["error_id"] = error_id
    end
    
    return response
end

function generate_error_id()::String
    """
    ユニークなエラーIDを生成
    """
    timestamp = Dates.format(now(), "yyyymmddHHMMSS")
    random_part = rand(1000:9999)
    return "ERR_$(timestamp)_$(random_part)"
end

# カスタム例外型の定義
struct ValidationError <: Exception
    message::String
    field::String
    value::Any
end

struct AuthenticationError <: Exception
    message::String
    username::String
end

struct AuthorizationError <: Exception
    message::String
    required_permission::String
    user_role::String
end

struct DatabaseConnectionError <: Exception
    message::String
    connection_string::String
end

struct ExternalServiceError <: Exception
    message::String
    service_name::String
    status_code::Int
end

# エラー処理のヘルパー関数
function validate_required_field(value::Any, field_name::String)
    """
    必須フィールドの検証
    """
    if value === nothing || value === missing || (value isa String && isempty(strip(value)))
        throw(ValidationError("$field_name は必須です", field_name, value))
    end
end

function validate_field_length(value::String, field_name::String, max_length::Int)
    """
    フィールド長の検証
    """
    if length(value) > max_length
        throw(ValidationError("$field_name は $max_length 文字以内である必要があります", field_name, value))
    end
end

function validate_positive_number(value::Number, field_name::String)
    """
    正の数値の検証
    """
    if value < 0
        throw(ValidationError("$field_name は0以上である必要があります", field_name, value))
    end
end

function with_error_handling(operation_name::String, func::Function, args...)
    """
    エラーハンドリング付きで関数を実行
    """
    try
        return func(args...)
    catch e
        error_message = handle_database_error(e, operation_name)
        rethrow(e)
    end
end

# リソース管理のヘルパー
function with_resource_cleanup(resource_creator::Function, resource_user::Function, resource_cleanup::Function)
    """
    リソースの自動クリーンアップ
    """
    resource = nothing
    try
        resource = resource_creator()
        return resource_user(resource)
    finally
        if resource !== nothing
            try
                resource_cleanup(resource)
            catch cleanup_error
                log_warning("リソースクリーンアップ中にエラーが発生しました", Dict(
                    "error" => string(cleanup_error)
                ))
            end
        end
    end
end

end