local key = "__relapsegtk_session_v2"
local env = getgenv()
local existing = env[key]
if existing then
    existing.publish()
    return
end

local safeCall = clonefunction(pcall)
local protectedCall = clonefunction(xpcall)
local compile = clonefunction(loadstring)
local raise = clonefunction(error)
local getEnvironment = clonefunction(gettenv)
local frameInfo = clonefunction(debug.info)
local defer = clonefunction(task.defer)
local stringify = clonefunction(tostring)
local running = clonefunction(coroutine.running)
local peers = {}
local owned = setmetatable({}, { __mode = "k" })
local busy = setmetatable({}, { __mode = "k" })
local state = {}
local limit = 4096

local function bounded(text)
    local truncated = #text > limit
    text = string.sub(text, 1, limit)
    if truncated then
        while #text > 0 and not utf8.len(text) and #text > limit - 4 do
            text = string.sub(text, 1, -2)
        end
    end
    if not utf8.len(text) then
        text = string.gsub(text, "[\128-\255]", function(c)
            return string.format("\\x%02x", string.byte(c))
        end)
    end
    text = string.gsub(text, "[%z\1-\8\11-\31\127]", function(c)
        return string.format("\\x%02x", string.byte(c))
    end)
    if #text > limit - 20 then
        text = string.sub(text, 1, limit - 20)
        while not utf8.len(text) do text = string.sub(text, 1, -2) end
        truncated = true
    end
    return text .. (truncated and " … [truncated]" or "")
end

local function format(...)
    local parts, bytes = {}, 0
    local count = select("#", ...)
    for i = 1, math.min(count, 64) do
        local ok, text = safeCall(stringify, select(i, ...))
        text = bounded(ok and text or "<tostring failed>")
        parts[#parts + 1] = text
        bytes += #text + 1
        if bytes >= limit then break end
    end
    if count > #parts then parts[#parts + 1] = "…" end
    return bounded(table.concat(parts, "\t"))
end

local function detach(connection)
    peers[connection] = nil
end

local function capture(level, ...)
    local active = false
    for connection in peers do
        if not connection.Connected then detach(connection)
        elseif peers[connection].redirect then active = true end
    end
    if not active then return false end
    local thread = running()
    if busy[thread] then return true end
    busy[thread] = true
    local ok, text = safeCall(format, ...)
    busy[thread] = nil
    if not ok then text = "<output formatting failed>" end
    active = false
    for connection, peer in peers do
        if not connection.Connected then
            detach(connection)
        elseif peer.redirect then
            active = true
            local sent = safeCall(connection.Send, connection,
                { type = "output", entries = {{ level = level, text = text }}, dropped = peer.dropped })
            peer.dropped = sent and 0 or math.min(peer.dropped + 1, 2147483647)
        end
    end
    return active
end

for _, name in { "print", "warn", "info" } do
    local target = env[name]
    if type(target) == "function" then
        local original
        original = hookfunction(target, function(...)
            if owned[getEnvironment()] then
                local ok, redirected = safeCall(capture, name, ...)
                if ok and redirected then return end
            end
            return original(...)
        end)
    end
end

local function errorText(detail)
    local ok, text = safeCall(stringify, detail)
    return bounded(ok and text or "<unprintable error>")
end

local function emitError(text)
    local captured, redirected = safeCall(capture, "error", text)
    -- An xpcall handler cannot rethrow without replacing the original failure.
    if not captured or not redirected then defer(raise, text, 0) end
end

local function reportError(detail)
    local parts = { errorText(detail) }
    for level = 2, 128 do
        local source, line, name, fn = frameInfo(level, "slnf")
        if not fn or fn == protectedCall then break end
        if source ~= "[C]" then
            local location = source .. (line >= 0 and ":" .. line or "")
            parts[#parts + 1] = location .. (name ~= "" and " in " .. name or "")
        end
    end
    local text = bounded(table.concat(parts, "\n"))
    emitError(text)
    return text
end

function state.execute(source, name)
    -- Called by a normal executor submission, which already owns its sandbox.
    owned[getEnvironment()] = true
    local ok, script, failure = safeCall(compile, source, "=" .. name)
    if not ok or not script then
        emitError(errorText(ok and failure or script))
        return
    end
    -- Native xpcall is the scheduled root; our setup frames never enter this task.
    defer(protectedCall, script, reportError)
end

function state.publish()
    if state.channel and state.channel.IsPublished then return end
    local channel = RelapseChannel.new("relapsegtk.session.v2")
    state.channel = channel
    channel.Connected:Connect(function(connection)
        connection.Disconnected:Connect(function() detach(connection) end)
        connection.MessageReceived:Connect(function(message)
            if type(message) ~= "table" then
                connection:Close()
                return
            end
            if message.op == "configure" and message.version == 2 and type(message.redirect) == "boolean" then
                local peer = peers[connection] or { dropped = 0 }
                peer.redirect = message.redirect
                peers[connection] = peer
                if not safeCall(connection.Send, connection,
                    { type = "configured", version = 2, redirect = peer.redirect }) then
                    detach(connection)
                    connection:Close()
                end
            else
                connection:Close()
            end
        end)
    end)
end

env[key] = state
state.publish()
