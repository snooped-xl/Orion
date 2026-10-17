-- Execute the packaged client unchanged against deterministic Roblox/HTTP mocks.
-- Run from the Flutter project root: lua5.4 tool/bridge_client_smoke.lua
-- Or: python3 tool/bridge_client_smoke.py (uses the system Lua 5.4 library).
local file = assert(io.open('assets/bridge/Orion Bridge.lua', 'rb'))
local source = file:read('*a'); file:close()
-- Test-only access to local state is appended after the complete, real asset;
-- none of the bridge's functions, loops, or request code is substituted.
local exports = [[
_G.bridge_test = {
    hello = send_hello, log = enqueue_log, result = enqueue_result,
    dispatch = dispatch, execution = run_execution,
    encode = b64_encode, decode = b64_decode,
    queues = function() return log_queue, result_queue, execution_order end,
    identity = function() return username end,
}
]]
local function new_mock(options)
    options = options or {}
    local m = { now = 0, calls = {}, threads = {}, prints = {}, waits = {}, disconnects = 0 }
    local env = setmetatable({}, {__index = _G})
    env._G = env
    env.getgenv = function() return env end
    env.os = setmetatable({clock = function() return m.now end}, {__index = os})
    env.print = function(...) m.prints[#m.prints + 1] = table.concat({...}, ' ') end
    env.identifyexecutor = function() return 'Mock Executor', 'test-version' end
    local player = options.player or {DisplayName = 'Display Name', Name = 'account_code_name'}
    local players = setmetatable({}, {__index = function(_, key)
        if key == 'LocalPlayer' and m.now >= (options.ready_after or 0) then return player end
    end})
    local log_service = {MessageOut = {Connect = function(_, callback)
        if options.console_unavailable then error('Console access unavailable') end
        m.log_callback = callback
        return {Disconnect = function() m.disconnects = m.disconnects + 1 end}
    end}}
    local http_service = {
        GenerateGUID = function() return 'mock-session-guid' end,
        JSONDecode = function(_, value)
            if value == 'HELLO' then return {ok = true, identifier = 'User7'} end
            if value == 'ACK' then return {ok = true} end
            if value == 'EMPTY' then return {} end
            if m.payloads and m.payloads[value] then return m.payloads[value] end
            error('Invalid JSON')
        end,
    }
    env.game = {
        IsLoaded = function() return true end,
        GetService = function(_, name)
            if name == 'Players' then return players end
            if name == 'HttpService' then return http_service end
            if name == 'LogService' then return log_service end
            error('Unexpected service: ' .. name)
        end,
        HttpGet = function(_, url)
            m.calls[#m.calls + 1] = {Method = 'HttpGet', Url = url}
            if m.http_get then return m.http_get(url) end
            error('HttpGet unavailable in this scenario')
        end,
    }
    local function request(req)
        m.calls[#m.calls + 1] = req
        if m.handler then return m.handler(req) end
        return {StatusCode = 200, Body = req.Url:find('/hello', 1, true) and 'HELLO'
            or req.Url:find('/next', 1, true) and 'EMPTY' or 'ACK'}
    end
    if not options.http_get_only then env.request = request end
    env.task = {
        spawn = function(fn) m.threads[#m.threads + 1] = coroutine.create(fn) end,
        wait = function(seconds)
            seconds = seconds or 0
            m.waits[#m.waits + 1] = seconds
            m.now = m.now + math.max(seconds, .001)
            if options.cancel_at and m.now >= options.cancel_at then
                env.OrionBridgeGeneration = 2
            end
            local _, main = coroutine.running()
            if not main then coroutine.yield(seconds) end
            return seconds
        end,
    }
    env.loadstring = function(text, name) return load(text, name, 't', env) end
    env.queue_on_teleport = function(text) m.teleport = text end
    m.env, m.player = env, player
    function m:boot()
        local chunk = assert(load(source .. '\n' .. exports, '@Orion Bridge.lua', 't', env))
        chunk()
        self.api = env.bridge_test
    end
    function m:step(index, count)
        for _ = 1, count or 1 do
            local thread = assert(self.threads[index], 'missing coroutine ' .. tostring(index))
            if coroutine.status(thread) ~= 'dead' then
                local ok, failure = coroutine.resume(thread)
                assert(ok, failure)
            end
        end
    end
    function m:connect() self:step(2); self.calls = {} end
    function m:stop() self.env.OrionBridgeStop() end
    return m
end
local passed = 0
local function test(name, fn)
    local ok, failure = pcall(fn)
    if not ok then error('FAIL ' .. name .. ': ' .. tostring(failure), 0) end
    passed = passed + 1
    print('PASS ' .. name)
end
local function contains(text, literal) return text:find(literal, 1, true) ~= nil end
local function queues(m) return m.api.queues() end

test('DisplayName is sent in both compatible hello fields and generation', function()
    local m = new_mock(); m:boot(); m:step(2)
    local hello = m.calls[1]
    assert(hello.Method == 'POST' and contains(hello.Body, '"display_name":"Display Name"'))
    assert(contains(hello.Body, '"username":"Display Name"'))
    assert(not contains(hello.Body, 'account_code_name'))
    assert(contains(hello.Body, '"bridge_generation":"1"'))
    assert(contains(m.calls[2].Url, '&bridge_generation=1'))
    assert(contains(m.calls[2].Url, 'identifier=User7'))
    assert(m.teleport and contains(m.teleport, '/bridge.lua'))
    m:stop()
end)

test('GET hello fallback carries DisplayName and generation', function()
    local m = new_mock(); m:boot()
    m.handler = function(req)
        if req.Method == 'POST' then return {StatusCode = 405, Body = 'rejected'} end
        return {StatusCode = '200', Body = 'HELLO'}
    end
    assert(m.api.hello('http://test/port_bridge', 'port-bridge'))
    assert(contains(m.calls[2].Url, '&display_name=Display%20Name'))
    assert(contains(m.calls[2].Url, '&username=Display%20Name'))
    assert(contains(m.calls[2].Url, '&bridge_generation=1'))
    m:stop()
end)

test('LocalPlayer startup race waits briefly for the real display identity', function()
    local m = new_mock({ready_after = .15}); m:boot()
    assert(m.api.identity() == 'Display Name')
    assert(m.now >= .15 and m.now < .3)
    m:stop()
end)

test('LocalPlayer wait is bounded and later heartbeat refreshes identity', function()
    local m = new_mock({ready_after = 100}); m:boot()
    assert(m.api.identity() == 'Unknown')
    assert(m.now >= 5 and m.now < 5.1)
    m.now = 100
    assert(m.api.hello('http://test/port_bridge', 'port-bridge'))
    assert(m.api.identity() == 'Display Name')
    m:stop()
end)

test('missing blank or inaccessible DisplayName never exposes account Name', function()
    for _, mode in ipairs({'missing', 'blank', 'inaccessible'}) do
        local name_reads = 0
        local player = setmetatable({}, {__index = function(_, key)
            if key == 'Name' then name_reads = name_reads + 1; error('account Name must never be read') end
            if key == 'DisplayName' then
                if mode == 'blank' then return '  ' end
                if mode == 'inaccessible' then error('property unavailable') end
            end
        end})
        local m = new_mock({player = player}); m:boot()
        assert(m.api.identity() == 'Unknown')
        assert(name_reads == 0 and m.now >= 5 and m.now < 5.1)
        m:stop()
    end
end)

test('DisplayName property readiness is bounded and receives a brief startup grace', function()
    local m = new_mock()
    m.player.DisplayName = nil
    setmetatable(m.player, {__index = function(_, key)
        if key == 'DisplayName' then return m.now >= .15 and 'Late Display' or '' end
    end})
    m:boot()
    assert(m.api.identity() == 'Late Display' and m.now >= .15 and m.now < .3)
    m:stop()
end)

test('stopping during player initialization installs no leaked listeners or tasks', function()
    local m = new_mock({ready_after = 100, cancel_at = .1}); m:boot()
    assert(m.now < .2 and #m.threads == 0 and not m.log_callback)
end)

test('logs wait for hello and retain FIFO entries until acknowledged JSON', function()
    local m = new_mock(); m:boot()
    m.api.log('print', 'first'); m.api.log('warn', 'second')
    m:step(1); assert(#m.calls == 0 and #queues(m) == 2)
    m:connect()
    local mode = 'failed'
    m.handler = function()
        return {StatusCode = mode == 'failed' and 500 or 200,
            Body = mode == 'success' and 'ACK' or '<html>proxy error</html>'}
    end
    m:step(1); assert(#queues(m) == 2 and m.waits[#m.waits] == .5)
    mode = 'html'; m:step(1); assert(#queues(m) == 2)
    mode = 'success'; m:step(1)
    assert(#queues(m) == 1 and queues(m)[1].message == 'second')
    assert(m.waits[#m.waits] == .03)
    assert(contains(m.calls[#m.calls].Url, '&bridge_generation=1'))
    assert(contains(m.calls[#m.calls].Url, 'session_id=mock-session-guid'))
    m:stop()
end)

test('result outbox retries failed acks and takes priority over log backlog', function()
    local m = new_mock(); m:boot(); m:connect()
    m.api.log('print', 'backlog'); m.api.result('execution-1', false, 'script failed')
    local online = false
    m.handler = function() return {StatusCode = online and 200 or 503, Body = online and 'ACK' or 'offline'} end
    m:step(1)
    local logs, results = queues(m)
    assert(#logs == 1 and #results == 1 and contains(m.calls[1].Url, '/result'))
    online = true; m:step(1)
    logs, results = queues(m); assert(#logs == 1 and #results == 0)
    m:step(1); assert(#queues(m) == 0)
    m:stop()
end)

test('outboxes are bounded and stop clears retained data', function()
    local m = new_mock(); m:boot()
    for index = 1, 530 do m.api.log('print', tostring(index)) end
    local logs = queues(m); assert(#logs == 512 and logs[1].message == '19')
    m.api.log('print', string.rep('a', 9000)); assert(#logs[#logs].message == 8192)
    for index = 1, 140 do m.api.result('r' .. index, true) end
    local _, results = queues(m); assert(#results == 128 and results[1].id == 'r13')
    m:stop(); logs, results = queues(m)
    assert(#logs == 0 and #results == 0 and m.disconnects == 1)
end)

test('duplicate queued running and completed executions never run twice', function()
    local m = new_mock(); m:boot(); m:connect()
    local item = {id = 'same-id', source_b64 = m.api.encode('execution_count = (execution_count or 0) + 1')}
    m.payloads = {BATCH = {exec = item, execs = {item}}}
    m.api.dispatch('BATCH'); assert(#m.threads == 3)
    m.api.dispatch('BATCH'); assert(#m.threads == 3)
    m:step(3); assert(m.env.execution_count == 1)
    m.api.dispatch('BATCH'); assert(#m.threads == 3)
    local _, results = queues(m); assert(#results == 1)
    m:step(1); m.api.dispatch('BATCH')
    _, results = queues(m); assert(#results == 1 and m.env.execution_count == 1)
    m:stop()
end)

test('execution history stays bounded without retaining source text', function()
    local m = new_mock(); m:boot()
    for index = 1, 280 do
        m.api.execution({id = 'e' .. index, source_b64 = m.api.encode('return true')})
        m:step(#m.threads)
    end
    local _, _, history = queues(m); assert(#history == 256)
    assert(history[1] == 'e25' and history[#history] == 'e280')
    m:stop()
end)

test('yielding scripts leave polls and hello heartbeats responsive', function()
    local m = new_mock(); m:boot(); m:connect()
    m.api.execution({id = 'slow', source_b64 = m.api.encode('task.wait(1); script_finished = true')})
    m:step(3); assert(not m.env.script_finished)
    m:step(2, 3)
    local hello_count = 0
    for _, req in ipairs(m.calls) do if contains(req.Url, '/hello') then hello_count = hello_count + 1 end end
    assert(hello_count >= 1)
    m:step(3); assert(m.env.script_finished)
    m:stop()
end)

test('replacement generation rejects old HTTP fallback and old background tasks', function()
    local m = new_mock(); m:boot()
    m.handler = function()
        m.env.OrionBridgeGeneration = 2
        return {StatusCode = 503, Body = 'offline'}
    end
    assert(not m.api.hello('http://test/port_bridge', 'port-bridge'))
    assert(#m.calls == 1, 'old generation sent fallback HTTP')
    m:step(1); m:step(2)
    assert(#m.calls == 1)
    m:stop()
end)

test('rerunning bridge preserves session while advancing protocol generation', function()
    local m = new_mock(); m:boot(); m:connect()
    m:boot(); assert(m.env.OrionBridgeGeneration == 2 and m.disconnects == 1)
    m:step(1); m:step(2); assert(#m.calls == 0, 'old tasks kept sending')
    m:step(4)
    local hello = m.calls[1]
    assert(contains(hello.Body, '"session_id":"mock-session-guid"'))
    assert(contains(hello.Body, '"bridge_generation":"2"'))
    assert(contains(m.calls[2].Url, '&bridge_generation=2'))
    m:stop()
end)

test('all three transport fallbacks survive failed requests', function()
    local m = new_mock(); m:boot()
    m.handler = function(req)
        if contains(req.Url, '/compat_bridge') then
            return {StatusCode = 200, Body = contains(req.Url, '/hello') and 'HELLO' or 'EMPTY'}
        end
        return {StatusCode = 503, Body = 'offline'}
    end
    m:step(2)
    local port, stream, compat = false, false, false
    for _, req in ipairs(m.calls) do
        port = port or contains(req.Url, '/port_bridge/hello')
        stream = stream or contains(req.Url, '/stream_bridge/hello')
        compat = compat or contains(req.Url, '/compat_bridge/next')
    end
    assert(port and stream and compat)
    m:stop()
end)

test('HttpGet-only executors still connect and acknowledge outbox requests', function()
    local m = new_mock({http_get_only = true}); m:boot()
    m.http_get = function(url)
        return contains(url, '/hello') and 'HELLO' or contains(url, '/next') and 'EMPTY' or 'ACK'
    end
    m:connect(); m.api.log('warn', 'hello'); m:step(1)
    assert(#queues(m) == 0 and m.calls[1].Method == 'HttpGet')
    assert(contains(m.calls[1].Url, 'message_b64='))
    m:stop()
end)

test('optional console mirror failure does not prevent bridge startup', function()
    local m = new_mock({console_unavailable = true}); m:boot(); m:step(2)
    assert(#m.threads == 2 and #m.calls >= 2 and not m.log_callback)
    m:stop()
end)

test('unaccepted hello cannot replace the assigned client identifier', function()
    local m = new_mock(); m:boot(); m:connect()
    m.payloads = {REJECTED = {ok = false, identifier = 'WrongIdentifier'}}
    m.handler = function() return {StatusCode = 200, Body = 'REJECTED'} end
    assert(not m.api.hello('http://test/port_bridge', 'port-bridge'))
    assert(m.env.OrionBridgeIdentifier == 'User7')
    m:stop()
end)

test('base64 validates malformed data and survives broken executor crypto helpers', function()
    local m = new_mock(); m:boot()
    for _, value in ipairs({'', 'a', 'ab', 'abc', 'print("hello")', 'nul\0\255'}) do
        assert(m.api.decode(m.api.encode(value)) == value)
    end
    for _, bad in ipairs({'A', 'AA?A', 'AA=A', 'AA===', '===='}) do
        assert(not pcall(m.api.decode, bad))
    end
    m.env.syn = {crypt = {base64 = {encode = function() error('bad encode API') end,
        decode = function() error('bad decode API') end}}}
    assert(m.api.decode(m.api.encode('fallback works')) == 'fallback works')
    m:stop()
end)
print(('Orion Bridge Lua smoke: %d scenarios passed.'):format(passed))
