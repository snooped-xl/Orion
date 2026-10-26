-- Orion Bridge

local PORT_URL = "http://127.0.0.1:31337/port_bridge"
local STREAM_URL = "http://127.0.0.1:31337/stream_bridge"
local COMPAT_URL = "http://127.0.0.1:31337/compat_bridge"
local PROTOCOL_TOKEN = "orion-bridge-v2"
local RESTART_DELAY = 1
local LOG_LIMIT = 512
local MESSAGE_LIMIT = 8192
local RESULT_LIMIT = 128
local EXECUTION_HISTORY_LIMIT = 256
local PLAYER_WAIT_TIMEOUT = 5
local OUTBOX_RETRY_DELAY = 0.5

if game and type(game.IsLoaded) == "function" and not game:IsLoaded() then
    local ok, loaded = pcall(function() return game.Loaded end)
    if ok and loaded then loaded:Wait() end
end

local environment = getgenv and getgenv() or _G
if type(environment.OrionBridgeStop) == "function" then
    pcall(environment.OrionBridgeStop)
end

local generation = (tonumber(environment.OrionBridgeGeneration) or 0) + 1
environment.OrionBridgeGeneration = generation
local running = true
local active_url = PORT_URL
local log_queue = {}
local result_queue = {}
local pending_results = {}
local execution_history = {}
local execution_order = {}
local session_ready = false
local log_connection

local function is_current()
    return running and environment.OrionBridgeGeneration == generation
end

environment.OrionBridgeStop = function()
    running = false
    session_ready = false
    log_queue = {}
    result_queue = {}
    pending_results = {}
    if log_connection then
        pcall(function() log_connection:Disconnect() end)
        log_connection = nil
    end
end

local request_api = request or http_request or (syn and syn.request)

local function with_protocol(url)
    local separator = url:find("?", 1, true) and "&" or "?"
    return url .. separator .. "protocol=" .. PROTOCOL_TOKEN
end

local function raw_get(url)
    if not is_current() then return nil, "Bridge stopped" end
    url = with_protocol(url)
    -- Prefer the request API so an expired session's 409 is recognised and
    -- triggers a fresh hello instead of treating an error page as a poll.
    if request_api then
        local ok, response = pcall(request_api, {
            Url = url,
            Method = "GET",
            Headers = { ["X-Orion-Bridge-Protocol"] = PROTOCOL_TOKEN },
        })
        if not is_current() then return nil, "Bridge stopped" end
        if ok and type(response) == "table" then
            local status = tonumber(response.StatusCode or response.status)
            local body = response.Body or response.body
            if (status == nil or status == 200) and body then return body end
            return nil, "HTTP " .. tostring(status)
        end
    end
    if game and type(game.HttpGet) == "function" then
        local ok, body = pcall(function() return game:HttpGet(url, true) end)
        if not is_current() then return nil, "Bridge stopped" end
        if ok and body then return body end
        return nil, tostring(body)
    end
    return nil, "No HTTP API available"
end

local function raw_post(url, body)
    if not is_current() or not request_api then return false, nil end
    url = with_protocol(url)
    local ok, response = pcall(request_api, {
        Url = url,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json",
            ["X-Orion-Bridge-Protocol"] = PROTOCOL_TOKEN,
        },
        Body = body,
    })
    if not is_current() or not ok or type(response) ~= "table" then return false, nil end
    local status = tonumber(response.StatusCode or response.status)
    local response_body = response.Body or response.body
    return status == nil or status == 200, response_body
end

local function json_escape(value)
    -- JSON requires every control byte to be escaped, including tabs/NUL.
    return tostring(value):gsub('[%z\1-\31\\"]', function(character)
        if character == "\\" then return "\\\\" end
        if character == '"' then return '\\"' end
        return string.format("\\u%04X", character:byte())
    end)
end

local function json_string(value)
    return "\"" .. json_escape(value) .. "\""
end

local function url_encode(value)
    return tostring(value):gsub("([^%w%-_.~])", function(character)
        return string.format("%%%02X", character:byte())
    end)
end

local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function pure_b64_encode(value)
    local result = {}
    for index = 1, #value, 3 do
        local a, b, c = value:byte(index, index + 2)
        b, c = b or 0, c or 0
        local packed = a * 65536 + b * 256 + c
        result[#result + 1] = alphabet:sub(math.floor(packed / 262144) % 64 + 1, math.floor(packed / 262144) % 64 + 1)
        result[#result + 1] = alphabet:sub(math.floor(packed / 4096) % 64 + 1, math.floor(packed / 4096) % 64 + 1)
        result[#result + 1] = index + 1 > #value and "=" or alphabet:sub(math.floor(packed / 64) % 64 + 1, math.floor(packed / 64) % 64 + 1)
        result[#result + 1] = index + 2 > #value and "=" or alphabet:sub(packed % 64 + 1, packed % 64 + 1)
    end
    return table.concat(result)
end

local function b64_encode(value)
    local ok, encoded = pcall(function()
        if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.encode then
            return syn.crypt.base64.encode(value)
        end
        if crypt and crypt.base64 and crypt.base64.encode then
            return crypt.base64.encode(value)
        end
        if base64 and base64.encode then return base64.encode(value) end
    end)
    if ok and type(encoded) == "string" then return encoded end
    return pure_b64_encode(value)
end

local function normalize_b64(value)
    if type(value) ~= "string" then error("Invalid base64 payload") end
    value = value:gsub("%s", "")
    local padding = value:match("=+$") or ""
    local data = value:sub(1, #value - #padding)
    if #padding > 2 or data:find("[^A-Za-z0-9+/]")
        or (#padding > 0 and #value % 4 ~= 0) or #data % 4 == 1 then
        error("Invalid base64 payload")
    end
    if #padding == 0 then
        local remainder = #value % 4
        if remainder == 2 then value = value .. "==" end
        if remainder == 3 then value = value .. "=" end
    end
    return value
end

local function pure_b64_decode(value)
    local lookup = {}
    for index = 1, #alphabet do lookup[alphabet:sub(index, index)] = index - 1 end
    local result = {}
    value = normalize_b64(value)
    for index = 1, #value, 4 do
        local a = lookup[value:sub(index, index)]
        local b = lookup[value:sub(index + 1, index + 1)]
        local c_char = value:sub(index + 2, index + 2)
        local d_char = value:sub(index + 3, index + 3)
        local c = lookup[c_char] or 0
        local d = lookup[d_char] or 0
        if a == nil or b == nil then error("Invalid base64 payload") end
        result[#result + 1] = string.char(a * 4 + math.floor(b / 16))
        if c_char ~= "=" and c_char ~= "" then
            result[#result + 1] = string.char((b % 16) * 16 + math.floor(c / 4))
        end
        if d_char ~= "=" and d_char ~= "" then
            result[#result + 1] = string.char((c % 4) * 64 + d)
        end
    end
    return table.concat(result)
end

local function b64_decode(value)
    value = normalize_b64(value)
    local ok, decoded = pcall(function()
        if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode then
            return syn.crypt.base64.decode(value)
        end
        if crypt and crypt.base64 and crypt.base64.decode then
            return crypt.base64.decode(value)
        end
        if base64 and base64.decode then return base64.decode(value) end
    end)
    if ok and type(decoded) == "string" then return decoded end
    return pure_b64_decode(value)
end

local function enqueue_log(level, message)
    if not is_current() then return end
    if #log_queue >= LOG_LIMIT then table.remove(log_queue, 1) end
    log_queue[#log_queue + 1] = { level = level, message = tostring(message):sub(1, MESSAGE_LIMIT) }
end

local session_url
local decode_json

local function acknowledged(body)
    local response = decode_json(body)
    return type(response) == "table" and response.ok == true
end

local function send_log(level, message)
    if not is_current() or not session_ready then return false end
    local body = "{\"level\":" .. json_string(level) .. ",\"message\":" .. json_string(message) .. "}"
    local sent, response = raw_post(session_url(active_url, "/log"), body)
    if sent and acknowledged(response) then return true end
    return acknowledged(raw_get(session_url(active_url, "/log") .. "&level=" .. url_encode(level)
        .. "&message_b64=" .. url_encode(b64_encode(message))))
end

local function install_console_mirror()
    local ok, log_service = pcall(function() return game:GetService("LogService") end)
    if not ok or not log_service or not log_service.MessageOut then return end
    log_connection = log_service.MessageOut:Connect(function(message, message_type)
        if not is_current() then return end
        local kind = tostring(message_type)
        local level = "print"
        if kind:find("Warning") then
            level = "warn"
        elseif kind:find("Error") then
            level = "error"
        elseif kind:find("Info") then
            level = "info"
        end
        enqueue_log(level, message)
    end)
end


decode_json = function(value)
    local ok, service = pcall(function() return game:GetService("HttpService") end)
    if not ok or not service then return nil end
    local decoded_ok, decoded = pcall(function() return service:JSONDecode(value) end)
    return decoded_ok and decoded or nil
end

local function clean_player_name(value)
    if type(value) ~= "string" then return nil end
    local clean = value:gsub("[%z\1-\31\127]", "")
        :gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 128)
    return clean ~= "" and clean or nil
end

local function resolve_username(wait_timeout)
    local ok, players = pcall(function() return game:GetService("Players") end)
    if not ok or not players then return "Unknown" end
    local deadline = os.clock() + (wait_timeout or 0)
    repeat
        local player_ok, player = pcall(function() return players.LocalPlayer end)
        if player_ok and player then
            local display_ok, display_name = pcall(function() return player.DisplayName end)
            local display = display_ok and clean_player_name(display_name) or nil
            if display then return display end
        end
        if not is_current() or os.clock() >= deadline then break end
        task.wait(0.05)
    until false
    -- Never substitute the account Name/code name for a missing display name.
    -- A later hello refreshes this placeholder once the player is ready.
    return "Unknown"
end

local function create_session_id()
    if type(environment.OrionBridgeSessionId) == "string" and environment.OrionBridgeSessionId ~= "" then
        return environment.OrionBridgeSessionId
    end
    local ok, service = pcall(function() return game:GetService("HttpService") end)
    local guid_ok, guid = false, nil
    if ok and service and type(service.GenerateGUID) == "function" then
        guid_ok, guid = pcall(function() return service:GenerateGUID(false) end)
    end
    local value = guid_ok and tostring(guid)
        or ("session-" .. tostring(os.clock()) .. "-" .. tostring(math.random(100000, 999999)))
    environment.OrionBridgeSessionId = value
    return value
end

local function resolve_executor_name()
    local ok, name = pcall(function()
        return identifyexecutor and identifyexecutor()
            or getexecutorname and getexecutorname()
    end)
    if not ok or type(name) ~= "string" then return "Unknown" end
    local clean = name:gsub("[%z\1-\31\127]", "")
        :gsub("^%s+", ""):gsub("%s+$", ""):sub(1, 64)
    return clean ~= "" and clean or "Unknown"
end

local executor_name = resolve_executor_name()
local username = resolve_username(PLAYER_WAIT_TIMEOUT)
if not is_current() then return end
local session_id = create_session_id()
local active_identifier = type(environment.OrionBridgeIdentifier) == "string"
    and environment.OrionBridgeIdentifier
    or "User1"

session_url = function(base_url, path)
    return base_url .. path
        .. "?session_id=" .. url_encode(session_id)
        .. "&identifier=" .. url_encode(active_identifier)
        .. "&bridge_generation=" .. url_encode(generation)
end

local function send_hello(base_url, client)
    if not is_current() then return false end
    -- Refresh on heartbeat too, so a late player or a display-name change
    -- updates the existing session rather than leaving a stale account name.
    username = resolve_username(0)
    local body = "{\"client\":" .. json_string(client)
        .. ",\"version\":2"
        .. ",\"executor_name\":" .. json_string(executor_name)
        .. ",\"session_id\":" .. json_string(session_id)
        .. ",\"bridge_generation\":" .. json_string(generation)
        .. ",\"requested_identifier\":" .. json_string(active_identifier)
        .. ",\"display_name\":" .. json_string(username)
        .. ",\"username\":" .. json_string(username) .. "}"
    local sent, response_body = raw_post(base_url .. "/hello", body)
    if not sent then
        response_body = raw_get(base_url .. "/hello?client=" .. url_encode(client)
            .. "&version=2"
            .. "&executor_name=" .. url_encode(executor_name)
            .. "&session_id=" .. url_encode(session_id)
            .. "&bridge_generation=" .. url_encode(generation)
            .. "&requested_identifier=" .. url_encode(active_identifier)
            .. "&display_name=" .. url_encode(username)
            .. "&username=" .. url_encode(username))
    end
    local response = decode_json(response_body)
    local accepted = type(response) == "table" and response.ok == true
        and type(response.identifier) == "string" and response.identifier ~= ""
    if accepted then
        active_identifier = response.identifier
        environment.OrionBridgeIdentifier = active_identifier
    end
    return accepted
end

local function send_result(id, succeeded, failure)
    if not is_current() or not session_ready then return false end
    local body = "{\"id\":" .. json_string(id) .. ",\"ok\":" .. tostring(succeeded)
    if not succeeded then body = body .. ",\"error\":" .. json_string(failure or "unknown error") end
    body = body .. "}"
    local sent, response = raw_post(session_url(active_url, "/result"), body)
    if sent and acknowledged(response) then return true end
    local url = session_url(active_url, "/result") .. "&id=" .. url_encode(id) .. "&ok=" .. tostring(succeeded)
    if not succeeded then url = url .. "&error_b64=" .. url_encode(b64_encode(failure or "unknown error")) end
    return acknowledged(raw_get(url))
end

local function enqueue_result(id, succeeded, failure)
    if not is_current() then return end
    id = tostring(id)
    if pending_results[id] then return end
    failure = failure and tostring(failure):sub(1, MESSAGE_LIMIT) or nil
    if #result_queue >= RESULT_LIMIT then
        local dropped = table.remove(result_queue, 1)
        pending_results[dropped.id] = nil
    end
    local entry = { id = id, succeeded = succeeded, failure = failure }
    pending_results[id] = entry
    result_queue[#result_queue + 1] = entry
end

local function run_log_sender()
    while is_current() do
        if not session_ready then
            task.wait(0.1)
        else
            local result = result_queue[1]
            local entry = result or log_queue[1]
            if not entry then
                task.wait(0.05)
            else
                local ok, delivered
                if result then
                    ok, delivered = pcall(send_result, entry.id, entry.succeeded, entry.failure)
                    if ok and delivered then
                        if result_queue[1] == entry then table.remove(result_queue, 1) end
                        if pending_results[entry.id] == entry then pending_results[entry.id] = nil end
                    end
                else
                    ok, delivered = pcall(send_log, entry.level, entry.message)
                    if ok and delivered and log_queue[1] == entry then table.remove(log_queue, 1) end
                end
                -- Always yield, even for an HTTP API that completes immediately.
                -- Polling and yielding user scripts must keep their heartbeat.
                task.wait(ok and delivered and 0.03 or OUTBOX_RETRY_DELAY)
            end
        end
    end
end

local function remember_execution(id)
    local previous = execution_history[id]
    if previous then
        if not previous.running then enqueue_result(id, previous.succeeded, previous.failure) end
        return nil
    end
    if #execution_order >= EXECUTION_HISTORY_LIMIT then
        local removed = false
        for index, remembered_id in ipairs(execution_order) do
            if not execution_history[remembered_id].running then
                execution_history[remembered_id] = nil
                table.remove(execution_order, index)
                removed = true
                break
            end
        end
        if not removed then
            enqueue_result(id, false, "Too many simultaneous Orion executions")
            return nil
        end
    end
    local record = { running = true }
    execution_history[id] = record
    execution_order[#execution_order + 1] = id
    return record
end

local function execute_source(source)
    local compiler = loadstring or load
    if type(compiler) ~= "function" then error("No script compiler is available") end
    local chunk, compile_error = compiler(source, "@orion_bridge")
    if type(chunk) ~= "function" then error(tostring(compile_error or "compile failed")) end
    return chunk()
end

local function run_execution(item)
    if not is_current() then return end
    local id = tostring(item.id)
    local record = remember_execution(id)
    if not record then return end
    task.spawn(function()
        if not is_current() then return end
        local decoded_ok, source = pcall(b64_decode, item.source_b64)
        local succeeded, failure
        if not decoded_ok or type(source) ~= "string" then
            succeeded, failure = false, "base64 decode failed"
        else
            succeeded, failure = pcall(execute_source, source)
            failure = not succeeded and tostring(failure):sub(1, MESSAGE_LIMIT) or nil
        end
        if not is_current() then return end
        record.running = false
        record.succeeded = succeeded
        record.failure = failure
        enqueue_result(id, succeeded, failure)
    end)
end

local function dispatch(body)
    if not is_current() then return end
    if type(body) ~= "string" or body == "" then return end
    local payload = decode_json(body)
    if type(payload) ~= "table" then return end
    if type(payload.exec) == "table" and payload.exec.id and payload.exec.source_b64 then
        run_execution(payload.exec)
    end
    if type(payload.execs) == "table" then
        for _, item in ipairs(payload.execs) do
            if type(item) == "table" and item.id and item.source_b64 then run_execution(item) end
        end
    end
end

local function report_executor()
    if type(identifyexecutor) ~= "function" then
        print("Executor Being Used: Unknown")
        return
    end
    local ok, name, version = pcall(identifyexecutor)
    if not ok then
        print("Executor Being Used: Unknown")
        return
    end
    print("Executor Being Used: " .. tostring(name or "Unknown"))
    print("Executor Version: " .. tostring(version or "Unknown"))
end

local function run_transport(base_url, client)
    if not is_current() then return true end
    session_ready = false
    active_url = base_url
    if not send_hello(base_url, client) then return false, "Hello failed" end
    if not is_current() then return true end
    session_ready = true
    local announced = false
    local poll_count = 0
    while is_current() do
        local body, failure = raw_get(session_url(base_url, "/next"))
        if not is_current() then return true end
        if not body then
            session_ready = false
            return false, tostring(failure)
        end
        if not announced then
            announced = true
            print("[Orion Bridge] Connected through " .. client)
            report_executor()
        end
        dispatch(body)
        poll_count = poll_count + 1
        if poll_count >= 3 then
            poll_count = 0
            pcall(send_hello, base_url, client)
        end
        task.wait(0.03)
    end
    return true
end

local function try_transport(base_url, client)
    local succeeded, connected, failure = pcall(run_transport, base_url, client)
    if not succeeded then
        session_ready = false
        return false, tostring(connected)
    end
    return connected, failure
end

local function run_bridge()
    while is_current() do
        local ok = try_transport(PORT_URL, "port-bridge")
        if is_current() and not ok then ok = try_transport(STREAM_URL, "stream-bridge") end
        if is_current() and not ok then ok = try_transport(COMPAT_URL, "compat-bridge") end
        if is_current() and not ok then
            enqueue_log("error", "[Orion Bridge] All connection methods failed; retrying")
            task.wait(RESTART_DELAY)
        end
    end
end

pcall(install_console_mirror)
task.spawn(run_log_sender)
task.spawn(run_bridge)

local queue = queue_on_teleport or queueonteleport or (syn and syn.queue_on_teleport)
if type(queue) == "function" then
    pcall(function()
        queue([[
            pcall(function()
                if game and type(game.IsLoaded) == "function" and not game:IsLoaded() then
                    game.Loaded:Wait()
                end
                task.wait(1)
                local source = game:HttpGet("http://127.0.0.1:31337/bridge.lua")
                local compiler = loadstring or load
                if source and source ~= "" and type(compiler) == "function" then
                    local chunk = compiler(source, "@orion_bridge")
                    if type(chunk) == "function" then chunk() end
                end
            end)
        ]])
    end)
end
