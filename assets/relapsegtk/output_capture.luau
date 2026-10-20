-- SPDX-License-Identifier: GPL-3.0-only
-- Bundled from vpu00000/relapsegtk resources/scripts/output.luau.
-- Source: https://github.com/vpu00000/relapsegtk/blob/6e926d9022e0e3e5632eaf1465cf42f31e1a4c01/resources/scripts/output.luau
local key = "__relapsegtk_output_v1"
local env = getgenv()
local existing = env[key]
if existing then
    existing.publish()
    return
end

local safeCall = clonefunction(pcall)
local caller = clonefunction(checkcaller)
local stringify = clonefunction(tostring)
local running = coroutine.running
local peers, hooks = {}, {}
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
    if not caller() then return false end
    local active = false
    for connection in peers do
        if connection.Connected then active = true else detach(connection) end
    end
    if not active then return false end
    local thread = running()
    if busy[thread] then return true end
    busy[thread] = true
    local ok, text = safeCall(format, ...)
    busy[thread] = nil
    if not ok then text = "<output formatting failed>" end
    active = false
    for connection, dropped in peers do
        if not connection.Connected then
            detach(connection)
        else
            active = true
            local sent = safeCall(connection.Send, connection,
                { type = "output", entries = {{ level = level, text = text }}, dropped = dropped })
            peers[connection] = sent and 0 or math.min(dropped + 1, 2147483647)
        end
    end
    return active
end

local function install()
    for _, name in { "print", "warn", "info", "error" } do
        local target = env[name]
        if type(target) == "function" and not hooks[name] then
            local original
            original = hookfunction(target, newcclosure(function(...)
                local ok, redirected = true, false
                if next(peers) then
                    if name == "error" then
                        local message = ...
                        ok, redirected = safeCall(capture, name, message)
                    else
                        ok, redirected = safeCall(capture, name, ...)
                    end
                end
                if name == "error" or not ok or not redirected then
                    return original(...)
                end
            end))
            hooks[name] = original
        end
    end
end

function state.publish()
    if state.channel and state.channel.IsPublished then return end
    local channel = RelapseChannel.new("relapsegtk.output.v1")
    state.channel = channel
    channel.Connected:Connect(function(connection)
        connection.Disconnected:Connect(function() detach(connection) end)
        connection.MessageReceived:Connect(function(message)
            if type(message) ~= "table" or message.op ~= "subscribe" or message.version ~= 1 then
                connection:Close()
                return
            end
            local ok, detail = safeCall(install)
            if not ok then
                safeCall(connection.Send, connection, { type = "failed", detail = bounded(stringify(detail)) })
                return
            end
            peers[connection] = peers[connection] or 0
            if not safeCall(connection.Send, connection, { type = "subscribed", version = 1 }) then
                detach(connection)
                connection:Close()
            end
        end)
    end)
end

env[key] = state
state.publish()
