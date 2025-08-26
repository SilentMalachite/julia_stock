module ViewHelpers

using Genie.Renderers.Html
using Dates

export form_input, form_select, form_button, form_textarea
export stock_path, stocks_path, new_stock_path, edit_stock_path
export format_currency, format_quantity, format_datetime
export flash_messages

# フォームヘルパー
function form_input(name::String, value::String=""; type::String="text", label::String="", placeholder::String="", required::Bool=false, class::String="form-control")
    label_html = isempty(label) ? "" : """<label for="$name">$label</label>"""
    required_attr = required ? "required" : ""
    
    return """
    <div class="form-group">
        $label_html
        <input type="$type" id="$name" name="$name" value="$value" placeholder="$placeholder" class="$class" $required_attr>
    </div>
    """
end

function form_select(name::String, options::Vector, selected::String=""; label::String="", required::Bool=false, class::String="form-control")
    label_html = isempty(label) ? "" : """<label for="$name">$label</label>"""
    required_attr = required ? "required" : ""
    
    options_html = join([
        """<option value="$value" $(value == selected ? "selected" : "")>$text</option>"""
        for (value, text) in options
    ])
    
    return """
    <div class="form-group">
        $label_html
        <select id="$name" name="$name" class="$class" $required_attr>
            $options_html
        </select>
    </div>
    """
end

function form_textarea(name::String, value::String=""; label::String="", placeholder::String="", rows::Int=3, class::String="form-control")
    label_html = isempty(label) ? "" : """<label for="$name">$label</label>"""
    
    return """
    <div class="form-group">
        $label_html
        <textarea id="$name" name="$name" placeholder="$placeholder" rows="$rows" class="$class">$value</textarea>
    </div>
    """
end

function form_button(text::String; type::String="submit", class::String="btn btn-primary")
    return """<button type="$type" class="$class">$text</button>"""
end

# URLヘルパー
function stock_path(id::Int)
    return "/stocks/$id"
end

function stocks_path()
    return "/stocks"
end

function new_stock_path()
    return "/stocks/new"
end

function edit_stock_path(id::Int)
    return "/stocks/$id/edit"
end

# フォーマットヘルパー
function format_currency(amount::Number; symbol::String="¥")
    formatted = string(round(amount, digits=0))
    # 3桁ごとにカンマを挿入
    parts = []
    while length(formatted) > 3
        pushfirst!(parts, formatted[end-2:end])
        formatted = formatted[1:end-3]
    end
    pushfirst!(parts, formatted)
    return symbol * join(parts, ",")
end

function format_quantity(quantity::Number, unit::String)
    return "$(quantity) $(unit)"
end

function format_datetime(dt::DateTime; format::String="yyyy年mm月dd日 HH:MM")
    return Dates.format(dt, format)
end

# フラッシュメッセージ
function flash_messages(messages::Dict{String, String})
    if isempty(messages)
        return ""
    end
    
    html = ""
    for (type, message) in messages
        alert_class = type == "error" ? "alert-danger" : "alert-$type"
        html *= """
        <div class="alert $alert_class alert-dismissible fade show" role="alert">
            $message
            <button type="button" class="close" data-dismiss="alert" aria-label="Close">
                <span aria-hidden="true">&times;</span>
            </button>
        </div>
        """
    end
    
    return html
end

end # module
