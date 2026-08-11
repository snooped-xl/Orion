-- Orion Bridge

local PORT_URL = "http://127.0.0.1:31337/port_bridge"
local STREAM_URL = "http://127.0.0.1:31337/stream_bridge"
local COMPAT_URL = "http://127.0.0.1:31337/compat_bridge"
local PROTOCOL_TOKEN = "orion-bridge-v2"
local RESTART_DELAY = 1
local LOG_LIMIT = 512

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
local log_connection

local function is_current()
    return running and environment.OrionBridgeGeneration == generation
end

environment.OrionBridgeStop = function()
    running = false
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
    url = with_protocol(url)
    if game and type(game.HttpGet) == "function" then
        local ok, body = pcall(function() return game:HttpGet(url) end)
        if ok and body then return body end
    end
    if request_api then
        local ok, response = pcall(request_api, { Url = url, Method = "GET" })
        if ok and response then
            local status = response.StatusCode or response.status
            local body = response.Body or response.body
            if (status == nil or status == 200) and body then return body end
            return nil, "HTTP " .. tostring(status)
        end
        return nil, tostring(response)
    end
    return nil, "No HTTP API available"
end

local function raw_post(url, body)
    if not request_api then return false, nil end
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
    if not ok or not response then return false, nil end
    local status = response.StatusCode or response.status
    local response_body = response.Body or response.body
    return status == nil or status == 200, response_body
end

local function json_escape(value)
    return tostring(value)
        :gsub("\\", "\\\\")
        :gsub("\"", "\\\"")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
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
    if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.encode then
        return syn.crypt.base64.encode(value)
    end
    if crypt and crypt.base64 and crypt.base64.encode then
        return crypt.base64.encode(value)
    end
    if base64 and base64.encode then return base64.encode(value) end
    return pure_b64_encode(value)
end

local function pure_b64_decode(value)
    local lookup = {}
    for index = 1, #alphabet do lookup[alphabet:sub(index, index)] = index - 1 end
    local result = {}
    value = tostring(value):gsub("%s", "")
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
    if syn and syn.crypt and syn.crypt.base64 and syn.crypt.base64.decode then
        return syn.crypt.base64.decode(value)
    end
    if crypt and crypt.base64 and crypt.base64.decode then
        return crypt.base64.decode(value)
    end
    if base64 and base64.decode then return base64.decode(value) end
    return pure_b64_decode(value)
end

local function enqueue_log(level, message)
    if not is_current() then return end
    if #log_queue >= LOG_LIMIT then table.remove(log_queue, 1) end
    log_queue[#log_queue + 1] = { level = level, message = tostring(message) }
end

local session_url

local function send_log(level, message)
    if not is_current() then return end
    local body = "{\"level\":" .. json_string(level) .. ",\"message\":" .. json_string(message) .. "}"
    if not raw_post(session_url(active_url, "/log"), body) then
        raw_get(session_url(active_url, "/log") .. "&level=" .. url_encode(level) .. "&message_b64=" .. url_encode(b64_encode(message)))
    end
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

local function run_log_sender()
    while is_current() do
        local entry = table.remove(log_queue, 1)
        if entry then
            pcall(send_log, entry.level, entry.message)
        else
            task.wait(0.05)
        end
    end
end

local function decode_json(value)
    local ok, service = pcall(function() return game:GetService("HttpService") end)
    if not ok or not service then return nil end
    local decoded_ok, decoded = pcall(function() return service:JSONDecode(value) end)
    return decoded_ok and decoded or nil
end

local function resolve_username()
    local ok, players = pcall(function() return game:GetService("Players") end)
    if not ok or not players then return "Unknown" end
    local player = players.LocalPlayer
    if not player then return "Unknown" end
    local name_ok, name = pcall(function() return player.Name end)
    return name_ok and tostring(name) or "Unknown"
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

local username = resolve_username()
local session_id = create_session_id()
local active_identifier = type(environment.OrionBridgeIdentifier) == "string"
    and environment.OrionBridgeIdentifier
    or "User1"

session_url = function(base_url, path)
    return base_url .. path
        .. "?session_id=" .. url_encode(session_id)
        .. "&identifier=" .. url_encode(active_identifier)
end

local function send_hello(base_url, client)
    local body = "{\"client\":" .. json_string(client)
        .. ",\"version\":2"
        .. ",\"session_id\":" .. json_string(session_id)
        .. ",\"requested_identifier\":" .. json_string(active_identifier)
        .. ",\"username\":" .. json_string(username) .. "}"
    local sent, response_body = raw_post(base_url .. "/hello", body)
    if not sent then
        response_body = raw_get(base_url .. "/hello?client=" .. url_encode(client)
            .. "&version=2"
            .. "&session_id=" .. url_encode(session_id)
            .. "&requested_identifier=" .. url_encode(active_identifier)
            .. "&username=" .. url_encode(username))
    end
    local response = decode_json(response_body)
    if type(response) == "table" and type(response.identifier) == "string" then
        active_identifier = response.identifier
        environment.OrionBridgeIdentifier = active_identifier
    end
    return sent or type(response_body) == "string"
end

local function send_result(id, succeeded, failure)
    if not is_current() then return end
    local body = "{\"id\":" .. json_string(id) .. ",\"ok\":" .. tostring(succeeded)
    if not succeeded then body = body .. ",\"error\":" .. json_string(failure or "unknown error") end
    body = body .. "}"
    if not raw_post(session_url(active_url, "/result"), body) then
        local url = session_url(active_url, "/result") .. "&id=" .. url_encode(id) .. "&ok=" .. tostring(succeeded)
        if not succeeded then url = url .. "&error_b64=" .. url_encode(b64_encode(failure or "unknown error")) end
        raw_get(url)
    end
end

local function execute_source(source)
    local compiler = loadstring or load
    if type(compiler) ~= "function" then error("No script compiler is available") end
    local chunk, compile_error = compiler(source, "@orion_bridge")
    if type(chunk) ~= "function" then error(tostring(compile_error or "compile failed")) end
    return chunk()
end

local function run_execution(item)
    task.spawn(function()
        if not is_current() then return end
        local decoded_ok, source = pcall(b64_decode, item.source_b64)
        if not decoded_ok then
            pcall(send_result, tostring(item.id), false, "base64 decode failed")
            return
        end
        local succeeded, failure = pcall(execute_source, source)
        pcall(send_result, tostring(item.id), succeeded, succeeded and nil or tostring(failure))
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
    active_url = base_url
    send_hello(base_url, client)
    if not is_current() then return true end
    local announced = false
    local poll_count = 0
    while is_current() do
        local body, failure = raw_get(session_url(base_url, "/next"))
        if not is_current() then return true end
        if not body then return false, tostring(failure) end
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

local function run_bridge()
    while is_current() do
        local ok = run_transport(PORT_URL, "port-bridge")
        if is_current() and not ok then ok = run_transport(STREAM_URL, "stream-bridge") end
        if is_current() and not ok then ok = run_transport(COMPAT_URL, "compat-bridge") end
        if is_current() and not ok then
            enqueue_log("error", "[Orion Bridge] All connection methods failed; retrying")
            task.wait(RESTART_DELAY)
        end
    end
end

install_console_mirror()
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
