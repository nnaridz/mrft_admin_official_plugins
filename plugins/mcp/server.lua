local plugin = Plugin("mcp")
local PROTOCOL_VERSION = "2025-06-18"

local PARSE_ERROR = -32700
local INVALID_REQUEST = -32600
local METHOD_NOT_FOUND = -32601
local INVALID_PARAMS = -32602

local NO_ARGUMENTS = { type = "object", additionalProperties = false }

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
    }
}

local toolsByName = {}
local toolList = {}
for i = 1, #tools do
    local tool = tools[i]
    toolsByName[tool.name] = tool
    toolList[i] = { name = tool.name, description = tool.description, inputSchema = tool.inputSchema }
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
    if not tool then
        return nil, { code = INVALID_PARAMS, message = "Unknown tool" }
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
        return { tools = toolList }
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
        local response = reply(body)
        if not response then
            res.writeHead(202)
            return res.send("")
        end
        res.writeHead(200, { ["Content-Type"] = "application/json" })
        res.send(json.encode(response))
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
