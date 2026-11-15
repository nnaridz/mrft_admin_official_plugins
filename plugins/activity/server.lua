local plugin = Plugin("activity")

local RESOURCE = GetCurrentResourceName()
local LOG_FILE = "storage/plugins/activity/log.json"
local MAX_ENTRIES = 1000
local MAX_TEXT = 300
local MAX_DETAIL = 2000

local function loadLog()
    local text = LoadResourceFile(RESOURCE, LOG_FILE)
    if not text then
        return { next = 1, entries = {} }
    end
    local log = json.decode(text)
    if type(log) ~= "table" or type(log.entries) ~= "table" or type(log.next) ~= "number" then
        error(("%s is not an activity log"):format(LOG_FILE))
    end
    return log
end

local log = loadLog()
local known = {}

for _, id in ipairs(GetPlayers()) do
    known[tonumber(id)] = GetPlayerName(id)
end

AddEventHandler("playerJoining", function()
    known[source] = GetPlayerName(source)
end)

local function nameOf(id)
    id = tonumber(id)
    if id == 0 then
        return "Console"
    end
    local name = GetPlayerName(id) or known[id]
    if name then
        return ("%s [%d]"):format(name, id)
    end
    return ("[%d]"):format(id)
end

local function clip(value, limit)
    value = tostring(value)
    if #value <= limit then
        return value
    end
    return value:sub(1, limit) .. "…"
end

local function persist()
    local text = json.encode(log)
    if not SaveResourceFile(RESOURCE, LOG_FILE, text, #text) then
        error(("could not write %s"):format(LOG_FILE))
    end
end

local function record(adminId, kind, text, detail)
    local entry = {
        id = log.next,
        time = os.time(),
        kind = kind,
        admin = nameOf(adminId),
        text = clip(text, MAX_TEXT),
        detail = detail and clip(detail, MAX_DETAIL) or nil
    }
    log.next = log.next + 1
    log.entries[#log.entries + 1] = entry
    if #log.entries > MAX_ENTRIES then
        table.remove(log.entries, 1)
    end
    persist()
    plugin.emit.admins("activity:entry", entry)
end

local function itemList(items)
    local parts = {}
    for _, item in ipairs(items) do
        parts[#parts + 1] = ("%s x%s"):format(item.name, item.qty)
    end
    return table.concat(parts, ", ")
end

local function onOff(state)
    return state and "เปิด" or "ปิด"
end

plugin.on("onKick", function(adminId, targetId, reason)
    record(adminId, "mod", ("เตะ %s · %s"):format(nameOf(targetId), reason))
end)

plugin.on("onBan", function(adminId, targetId, identifier, reason, duration)
    local who = targetId and nameOf(targetId) or identifier
    record(adminId, "mod", ("แบน %s (%s) · %s"):format(who, duration, reason))
end)

plugin.on("onBanInput", function(adminId, typedInput, reason, duration)
    record(adminId, "mod", ("แบน %s (%s) · %s"):format(typedInput, duration, reason))
end)

plugin.on("onRevokeBan", function(adminId, identifier, removed)
    if removed then
        record(adminId, "mod", ("ปลดแบน %s"):format(identifier))
    end
end)

plugin.on("onResetCharacter", function(adminId, targetId, identifier)
    record(adminId, "mod", ("รีตัวละคร %s (%s)"):format(nameOf(targetId), identifier))
end)

plugin.on("onClearItems", function(adminId, targetId)
    record(adminId, "mod", ("ล้างไอเทม %s"):format(nameOf(targetId)))
end)

plugin.on("onClearWeapons", function(adminId, targetId)
    record(adminId, "mod", ("ล้างอาวุธ %s"):format(nameOf(targetId)))
end)

plugin.on("onGive", function(adminId, targetId, items)
    record(adminId, "player", ("เสกให้ %s · %s"):format(nameOf(targetId), itemList(items)))
end)

plugin.on("onSetGroup", function(adminId, targetId, group)
    record(adminId, "player", ("เปลี่ยนยศ %s เป็น %s"):format(nameOf(targetId), group))
end)

plugin.on("onSetJob", function(adminId, targetId, jobName, jobGrade)
    record(adminId, "player", ("เปลี่ยนอาชีพ %s เป็น %s (%s)"):format(nameOf(targetId), jobName, jobGrade))
end)

plugin.on("onGoto", function(adminId, targetId)
    record(adminId, "player", ("วาร์ปไปหา %s"):format(nameOf(targetId)))
end)

plugin.on("onBring", function(adminId, targetId)
    record(adminId, "player", ("ดึง %s มาหา"):format(nameOf(targetId)))
end)

plugin.on("onSpectate", function(adminId, targetId)
    record(adminId, "player", ("ส่องดู %s"):format(nameOf(targetId)))
end)

plugin.on("onRequestScreen", function(adminId, targetId)
    record(adminId, "player", ("ดูจอ %s"):format(nameOf(targetId)))
end)

plugin.on("onPlayerAddonAction", function(adminId, addon, targetId)
    record(adminId, "player", ("ใช้ %s กับ %s"):format(addon, nameOf(targetId)))
end)

plugin.on("onAnnouncement", function(adminId, message)
    record(adminId, "world", ("ประกาศ · %s"):format(message))
end)

plugin.on("onSetWeather", function(adminId, weather)
    record(adminId, "world", ("เปลี่ยนสภาพอากาศเป็น %s"):format(weather))
end)

plugin.on("onSetTime", function(adminId, hour, minute)
    record(adminId, "world", ("ตั้งเวลาเป็น %02d:%02d"):format(hour, minute))
end)

plugin.on("onFreezeTime", function(adminId, state)
    record(adminId, "world", ("%sหยุดเวลา"):format(onOff(state)))
end)

plugin.on("onFreezeWeather", function(adminId, state)
    record(adminId, "world", ("%sหยุดสภาพอากาศ"):format(onOff(state)))
end)

plugin.on("onGiveAll", function(adminId, items, includeOffline)
    local scope = includeOffline and "ทุกคน (รวมออฟไลน์)" or "ทุกคนที่ออนไลน์"
    record(adminId, "world", ("เสกให้%s · %s"):format(scope, itemList(items)))
end)

plugin.on("onDeleteAllVehicles", function(adminId)
    record(adminId, "world", "ลบรถทั้งหมด")
end)

plugin.on("onDeleteAllProps", function(adminId)
    record(adminId, "world", "ลบพร็อพทั้งหมด")
end)

plugin.on("onDeleteNearbyVehicles", function(adminId, radius)
    record(adminId, "world", ("ลบรถในระยะ %s ม."):format(radius))
end)

plugin.on("onDeleteNearbyProps", function(adminId, radius)
    record(adminId, "world", ("ลบพร็อพในระยะ %s ม."):format(radius))
end)

plugin.on("onPlayerBlipsToggle", function(adminId, state)
    record(adminId, "world", ("%s Blips ผู้เล่น"):format(onOff(state)))
end)

plugin.on("onLiveMapToggle", function(adminId, state)
    record(adminId, "world", ("%s Live Map"):format(onOff(state)))
end)

plugin.on("onAddonAction", function(adminId, addon, state)
    if state == nil then
        record(adminId, "world", ("ใช้ %s"):format(addon))
    else
        record(adminId, "world", ("%s %s"):format(onOff(state), addon))
    end
end)

plugin.on("onExecuteCode", function(adminId, option, code, targetIds)
    local where = option == "server" and "server" or ("%s → %s"):format(option, targetIds)
    local first = code:match("^%s*([^\n]*)")
    record(adminId, "code", ("รันโค้ด (%s) · %s"):format(where, first), code)
end)

plugin.on("onReportSolved", function(adminId, caseId)
    record(adminId, "report", ("ปิดเคส #%s"):format(caseId))
end)

plugin.on("onReportGoto", function(adminId, caseId)
    record(adminId, "report", ("วาร์ปไปเคส #%s"):format(caseId))
end)

plugin.on("onAction", function(adminId, action, args)
    if action:find(".", 1, true) then
        record(adminId, "plugin", ("ใช้ %s"):format(action), json.encode(args))
    end
end)

plugin.actions.register("sync", {
    permission = false,
    quiet = true,
    validate = function(adminId)
        return plugin.players.admins()[adminId] ~= nil
    end,
    run = function(adminId)
        plugin.emit.player(adminId, "activity:history", log.entries)
    end
})
