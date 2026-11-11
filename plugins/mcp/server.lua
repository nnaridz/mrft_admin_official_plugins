local plugin = Plugin("mcp")
local PROTOCOL_VERSION = "2025-06-18"

local PARSE_ERROR = -32700
local INVALID_REQUEST = -32600
local METHOD_NOT_FOUND = -32601
local INVALID_PARAMS = -32602

local CONSOLE = 0
local HISTORY_SIZE = 100
local CLIENT_TIMEOUT_MS = 5000
local RESULT_EVENT = plugin.id .. ":clientResult"

local NO_ARGUMENTS = { type = "object", additionalProperties = false }

local function object(properties, required)
    return { type = "object", properties = properties, required = required, additionalProperties = false }
end

local PLAYER_ID = { type = "integer", description = "Server id of an online player" }

local function onlinePlayer(playerId)
    if not GetPlayerName(playerId) then
        error(("Player %s is not online"):format(tostring(playerId)))
    end
    return playerId
end

local function serializable(value)
    local kind = type(value)
    if kind == "table" then
        local copy = {}
        for key, item in pairs(value) do
            copy[tostring(key)] = serializable(item)
        end
        return copy
    end
    if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then
        return value
    end
    return tostring(value)
end

local history = {}
plugin.on("onAction", function(adminId, action, args)
    table.insert(history, 1, {
        time = os.time(),
        adminId = adminId,
        admin = adminId == CONSOLE and "Console" or GetPlayerName(adminId),
        action = action,
        args = serializable(args)
    })
    history[HISTORY_SIZE + 1] = nil
end)

local pending = {}
RegisterNetEvent(RESULT_EVENT, function(nonce, ok, encoded)
    local request = pending[nonce]
    local playerId = source
    if not request or not request.waiting[playerId] then
        return
    end
    request.waiting[playerId] = nil
    request.results[tostring(playerId)] = { ok = ok, result = json.decode(encoded) }
    request.left = request.left - 1
    if request.left == 0 then
        request.done:resolve()
    end
end)

local CLIENT_WRAPPER = [[
local function plain(value)
    local kind = type(value)
    if kind == "table" then
        local copy = {}
        for key, item in pairs(value) do copy[tostring(key)] = plain(item) end
        return copy
    end
    if kind == "string" or kind == "number" or kind == "boolean" or kind == "nil" then return value end
    return tostring(value)
end
local ok, value = pcall(function()
%s
end)
TriggerServerEvent(%q, %q, ok, json.encode({ value = plain(value) }))
]]

local function runOnClients(code, playerIds)
    local nonce = ("%08x%08x"):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff))
    local request = { waiting = {}, results = {}, left = #playerIds, done = promise.new() }
    local targets = {}
    for i = 1, #playerIds do
        local playerId = onlinePlayer(playerIds[i])
        request.waiting[playerId] = true
        targets[i] = tostring(playerId)
    end
    pending[nonce] = request
    plugin.actions.run(CONSOLE, "execute", CLIENT_WRAPPER:format(code, RESULT_EVENT, nonce), "client", table.concat(targets, ","))
    SetTimeout(CLIENT_TIMEOUT_MS, function()
        if request.left > 0 then
            request.done:resolve()
        end
    end)
    Citizen.Await(request.done)
    pending[nonce] = nil
    for playerId in pairs(request.waiting) do
        request.results[tostring(playerId)] = { ok = false, result = { value = "No reply within 5 seconds" } }
    end
    return request.results
end

local function runOnServer(code)
    local printed = {}
    local env = setmetatable({
        print = function(...)
            local parts = table.pack(...)
            for i = 1, parts.n do
                parts[i] = tostring(parts[i])
            end
            printed[#printed + 1] = table.concat(parts, "\t", 1, parts.n)
        end
    }, { __index = _G })
    local chunk, syntaxError = load(code, "=mcp", "t", env)
    if not chunk then
        return { ok = false, error = syntaxError, printed = printed }
    end
    local ok, value = pcall(chunk)
    plugin.log(CONSOLE, "DangerAction", ("MCP ran server code\n```lua\n%s\n```"):format(code))
    if not ok then
        return { ok = false, error = tostring(value), printed = printed }
    end
    return { ok = true, result = serializable(value), printed = printed }
end

local function playerAddons()
    local names = {}
    for name, addon in pairs(config.player_addons) do
        if addon.server_action or addon.target_client_action then
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

local tools = {
    {
        name = "server_info",
        description = "Server name, player count, player limit and admin resource version.",
        inputSchema = NO_ARGUMENTS,
        run = function()
            local resource = GetCurrentResourceName()
            return {
                hostname = GetConvar("sv_hostname", ""),
                players = GetNumPlayerIndices(),
                maxPlayers = GetConvarInt("sv_maxclients", 0),
                resource = resource,
                version = GetResourceMetadata(resource, "version", 0)
            }
        end
    },
    {
        name = "list_players",
        description = "Online players: server id, name, Steam identifier and ping. Players with a loaded character also carry character name, permission group and job.",
        inputSchema = NO_ARGUMENTS,
        run = function()
            local list = {}
            local online = GetPlayers()
            for i = 1, #online do
                local playerId = tonumber(online[i])
                local entry = {
                    id = playerId,
                    name = GetPlayerName(playerId),
                    steam = GetPlayerIdentifierByType(playerId, "steam"),
                    ping = GetPlayerPing(playerId)
                }
                local playerObj = framework.GetPlayer(playerId)
                if playerObj then
                    local job = framework.getJob(playerObj, playerId)
                    entry.character = framework.GetPlayerName(playerObj, playerId)
                    entry.group = framework.getGroup(playerObj, playerId)
                    entry.job = job.name
                    entry.grade = job.grade
                end
                list[#list + 1] = entry
            end
            return { players = list }
        end
    },
    {
        name = "get_player",
        description = "Everything known about one online player: every identifier, character name, group, job, ping, position, health and armour.",
        inputSchema = object({ id = PLAYER_ID }, { "id" }),
        run = function(args)
            local playerId = onlinePlayer(args.id)
            local ped = GetPlayerPed(playerId)
            local coords = GetEntityCoords(ped)
            local entry = {
                id = playerId,
                name = GetPlayerName(playerId),
                identifiers = GetPlayerIdentifiers(playerId),
                ping = GetPlayerPing(playerId),
                coords = { x = coords.x, y = coords.y, z = coords.z },
                heading = GetEntityHeading(ped),
                health = GetEntityHealth(ped),
                armour = GetPedArmour(ped)
            }
            local playerObj = framework.GetPlayer(playerId)
            if playerObj then
                local job = framework.getJob(playerObj, playerId)
                entry.character = framework.GetPlayerName(playerObj, playerId)
                entry.group = framework.getGroup(playerObj, playerId)
                entry.job = job.name
                entry.grade = job.grade
            end
            return entry
        end
    },
    {
        name = "list_reports",
        description = "Open player reports: case id, reporter, message, category, position, screenshot link and date.",
        inputSchema = NO_ARGUMENTS,
        run = function()
            return { reports = plugin.reports.list() }
        end
    },
    {
        name = "find_ban",
        description = "The active ban on an identifier (license:, steam:, discord: ...), or found = false. Times are unix seconds; expires_at is absent for a permanent ban.",
        inputSchema = object({ identifier = { type = "string" } }, { "identifier" }),
        run = function(args)
            local ban = plugin.bans.find(args.identifier)
            return { found = ban ~= nil, ban = ban }
        end
    },
    {
        name = "recent_actions",
        description = "Admin actions since the server started, newest first (at most 100): time, admin, action name and its arguments.",
        inputSchema = object({ limit = { type = "integer", minimum = 1, maximum = HISTORY_SIZE } }),
        run = function(args)
            local limit = args.limit or HISTORY_SIZE
            return { actions = { table.unpack(history, 1, math.min(limit, #history)) } }
        end
    },
    {
        name = "kick",
        group = "allow_moderation",
        description = "Kicks an online player with a reason they see on disconnect.",
        inputSchema = object({ id = PLAYER_ID, reason = { type = "string" } }, { "id", "reason" }),
        run = function(args)
            plugin.actions.run(CONSOLE, "kick", onlinePlayer(args.id), args.reason)
            return { kicked = args.id }
        end
    },
    {
        name = "ban",
        group = "allow_moderation",
        description = "Bans an online player by server id, or an offline identifier. Duration is \"forever\" or a number and a unit: \"12h\", \"3d\", \"1m\" (30 days), \"1y\".",
        inputSchema = object({
            id = PLAYER_ID,
            identifier = { type = "string", description = "Use instead of id for an offline player" },
            reason = { type = "string" },
            duration = { type = "string" }
        }, { "reason", "duration" }),
        run = function(args)
            if (args.id == nil) == (args.identifier == nil) then
                error("Give exactly one of id or identifier")
            end
            local identifier = args.identifier
            if args.id then
                identifier = plugin.players.get(onlinePlayer(args.id)).identifier
            end
            plugin.bans.add(CONSOLE, args.id, identifier, args.reason, args.duration)
            return { banned = identifier }
        end
    },
    {
        name = "unban",
        group = "allow_moderation",
        description = "Lifts the active ban on an identifier. removed is false when there was none.",
        inputSchema = object({ identifier = { type = "string" } }, { "identifier" }),
        run = function(args)
            return { removed = plugin.bans.remove(CONSOLE, args.identifier) }
        end
    },
    {
        name = "announce",
        group = "allow_moderation",
        description = "Shows a server-wide announcement to every player.",
        inputSchema = object({ message = { type = "string", minLength = 1 } }, { "message" }),
        run = function(args)
            plugin.actions.run(CONSOLE, "announcement", args.message)
            return { announced = true }
        end
    },
    {
        name = "set_job",
        group = "allow_players",
        description = "Sets an online player's job and grade.",
        inputSchema = object({ id = PLAYER_ID, job = { type = "string" }, grade = { type = "integer", minimum = 0 } }, { "id", "job", "grade" }),
        run = function(args)
            plugin.actions.run(CONSOLE, "setJob", onlinePlayer(args.id), args.job, args.grade)
            return { id = args.id, job = args.job, grade = args.grade }
        end
    },
    {
        name = "set_group",
        group = "allow_players",
        description = "Sets an online player's permission group, such as user or admin.",
        inputSchema = object({ id = PLAYER_ID, group = { type = "string" } }, { "id", "group" }),
        run = function(args)
            plugin.actions.run(CONSOLE, "setGroup", onlinePlayer(args.id), args.group)
            return { id = args.id, group = args.group }
        end
    },
    {
        name = "give_items",
        group = "allow_players",
        description = "Adds items to an online player's inventory.",
        inputSchema = object({
            id = PLAYER_ID,
            items = {
                type = "array",
                minItems = 1,
                items = object({ name = { type = "string" }, qty = { type = "integer", minimum = 1 } }, { "name", "qty" })
            }
        }, { "id", "items" }),
        run = function(args)
            plugin.actions.run(CONSOLE, "give", onlinePlayer(args.id), args.items)
            return { id = args.id, items = args.items }
        end
    },
    {
        name = "player_action",
        group = "allow_players",
        description = "Runs a player action from the admin menu on an online player, such as revive, heal or freeze.",
        inputSchema = function()
            return object({ action = { type = "string", enum = playerAddons() }, id = PLAYER_ID }, { "action", "id" })
        end,
        run = function(args)
            plugin.actions.run(CONSOLE, "playerAddonAction", args.action, onlinePlayer(args.id))
            return { id = args.id, action = args.action }
        end
    },
    {
        name = "execute_server",
        group = "allow_execute",
        description = "Runs Lua on the server inside the admin resource, with its globals and FiveM natives. Returns the chunk's return value and everything it printed. Logged to the DangerAction webhook.",
        inputSchema = object({ code = { type = "string", minLength = 1 } }, { "code" }),
        run = function(args)
            return runOnServer(args.code)
        end
    },
    {
        name = "execute_client",
        group = "allow_execute",
        description = "Runs Lua on the clients of online players and returns each one's return value, keyed by server id. Players that do not answer within 5 seconds are reported as failed.",
        inputSchema = object({
            code = { type = "string", minLength = 1 },
            ids = { type = "array", minItems = 1, items = PLAYER_ID }
        }, { "code", "ids" }),
        run = function(args)
            return { results = runOnClients(args.code, args.ids) }
        end
    }
}

local toolsByName = {}
for i = 1, #tools do
    toolsByName[tools[i].name] = tools[i]
end

local function enabled(tool)
    return tool.group == nil or plugin.config[tool.group] == true
end

local function listTools()
    local list = {}
    for i = 1, #tools do
        local tool = tools[i]
        if enabled(tool) then
            local schema = tool.inputSchema
            list[#list + 1] = { name = tool.name, description = tool.description, inputSchema = type(schema) == "function" and schema() or schema }
        end
    end
    return list
end

local function sameToken(given, expected)
    local diff = #given ~ #expected
    for i = 1, #expected do
        diff = diff | ((given:byte(i) or 0) ~ expected:byte(i))
    end
    return diff == 0
end

local function callTool(params)
    local tool = type(params) == "table" and toolsByName[params.name]
    if not tool or not enabled(tool) then
        return nil, { code = INVALID_PARAMS, message = "Unknown or disabled tool" }
    end

    local ok, output = pcall(tool.run, params.arguments or {})
    if not ok then
        print(("^1[MCP]^7 tool %s failed: %s"):format(tool.name, output))
        return { content = { { type = "text", text = tostring(output) } }, isError = true }
    end
    return { content = { { type = "text", text = json.encode(output) } }, structuredContent = output }
end

local methods = {
    initialize = function()
        return {
            protocolVersion = PROTOCOL_VERSION,
            capabilities = { tools = { listChanged = false } },
            serverInfo = {
                name = GetCurrentResourceName(),
                version = GetResourceMetadata(GetCurrentResourceName(), "version", 0)
            }
        }
    end,
    ping = function()
        return {}
    end,
    ["tools/list"] = function()
        return { tools = listTools() }
    end,
    ["tools/call"] = callTool
}

local function reply(body)
    local parsed, message = pcall(json.decode, body)
    if not parsed or type(message) ~= "table" then
        return { jsonrpc = "2.0", id = json.null, error = { code = PARSE_ERROR, message = "Body is not a JSON object" } }
    end
    if message.jsonrpc ~= "2.0" or message[1] ~= nil then
        return { jsonrpc = "2.0", id = json.null, error = { code = INVALID_REQUEST, message = "Expected one JSON-RPC 2.0 message" } }
    end
    if message.id == nil or message.method == nil then
        return nil
    end

    local method = methods[message.method]
    if not method then
        return { jsonrpc = "2.0", id = message.id, error = { code = METHOD_NOT_FOUND, message = "Method not found" } }
    end

    local result, failure = method(message.params)
    if failure then
        return { jsonrpc = "2.0", id = message.id, error = failure }
    end
    return { jsonrpc = "2.0", id = message.id, result = result }
end

local function refuse(res, status, text, headers)
    headers = headers or {}
    headers["Content-Type"] = "text/plain"
    res.writeHead(status, headers)
    res.send(text)
end

local function handle(req, res)
    if req.method ~= "POST" then
        return refuse(res, 405, "Method not allowed", { Allow = "POST" })
    end

    local headers = {}
    for name, value in pairs(req.headers) do
        headers[name:lower()] = value
    end

    if headers.origin then
        return refuse(res, 403, "Browser requests are not accepted")
    end

    local token = plugin.config.token
    if token == "" then
        return refuse(res, 503, "No token yet: generate one in the admin menu, Plugins page")
    end

    local given = (headers.authorization or ""):match("^Bearer (.+)$")
    if not given or not sameToken(given, token) then
        return refuse(res, 401, "Invalid token", { ["WWW-Authenticate"] = "Bearer" })
    end

    local version = headers["mcp-protocol-version"]
    if version and version ~= PROTOCOL_VERSION then
        return refuse(res, 400, "Unsupported MCP-Protocol-Version")
    end

    req.setDataHandler(function(body)
        CreateThread(function()
            local response = reply(body)
            if not response then
                res.writeHead(202)
                return res.send("")
            end
            res.writeHead(200, { ["Content-Type"] = "application/json" })
            res.send(json.encode(response))
        end)
    end)
end

-- http://<server>/<admin resource>/mcp
if plugin.http then
    plugin.http.route("*", "/", handle)
else
    -- Admin resources without the plugin API v2 give the whole resource's HTTP handler to one plugin
    SetHttpHandler(function(req, res)
        if req.path ~= "/mcp" then
            return refuse(res, 404, "Not found")
        end
        handle(req, res)
    end)
end
