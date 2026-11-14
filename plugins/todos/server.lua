local plugin = Plugin("todos")

local RESOURCE = GetCurrentResourceName()
local BOARD_FILE = "storage/plugins/todos/board.json"
local COLORS = { gray = true, red = true, amber = true, green = true, blue = true, violet = true }
local MAX_CARDS = 200
local MAX_ITEMS = 50
local MAX_TITLE = 80
local MAX_TEXT = 200
local MAX_COORD = 100000

local function loadBoard()
    local text = LoadResourceFile(RESOURCE, BOARD_FILE)
    if not text then
        return { next = 1, cards = {} }
    end
    local board = json.decode(text)
    if type(board) ~= "table" or type(board.cards) ~= "table" or type(board.next) ~= "number" then
        error(("%s is not a todos board"):format(BOARD_FILE))
    end
    return board
end

local board = loadBoard()

local function persist()
    local text = json.encode(board)
    if not SaveResourceFile(RESOURCE, BOARD_FILE, text, #text) then
        error(("could not write %s"):format(BOARD_FILE))
    end
end

local function cardCount()
    local count = 0
    for _ in pairs(board.cards) do
        count = count + 1
    end
    return count
end

local function isText(value, limit)
    return type(value) == "string" and #value <= limit
end

local function isCoord(value)
    return type(value) == "number" and value == value and math.abs(value) <= MAX_COORD
end

local function isItems(items)
    if type(items) ~= "table" or #items > MAX_ITEMS then
        return false
    end
    for _, item in ipairs(items) do
        if type(item) ~= "table" or not isText(item.text, MAX_TEXT) or type(item.done) ~= "boolean" then
            return false
        end
    end
    return true
end

local function cardProblem(card)
    if type(card) ~= "table" then return "ข้อมูลโน้ตไม่ถูกต้อง" end
    if card.id ~= nil and (type(card.id) ~= "string" or not board.cards[card.id]) then return "โน้ตนี้ถูกลบไปแล้ว" end
    if not isText(card.title, MAX_TITLE) then return ("ชื่อโน้ตยาวได้ไม่เกิน %d ตัวอักษร"):format(MAX_TITLE) end
    if not COLORS[card.color] then return "สีโน้ตไม่ถูกต้อง" end
    if not isCoord(card.x) or not isCoord(card.y) then return "ตำแหน่งโน้ตไม่ถูกต้อง" end
    if not isItems(card.items) then return ("เช็กลิสต์มีได้ไม่เกิน %d รายการ รายการละไม่เกิน %d ตัวอักษร"):format(MAX_ITEMS, MAX_TEXT) end
    if card.id == nil and cardCount() >= MAX_CARDS then return ("บอร์ดมีโน้ตได้ไม่เกิน %d ใบ"):format(MAX_CARDS) end
    return nil
end

local function isAdmin(adminId)
    return plugin.players.admins()[adminId] ~= nil
end

local function adminOnly(validateArgs)
    return function(adminId, args)
        if not isAdmin(adminId) then
            return false
        end
        if validateArgs then
            local problem = validateArgs(args)
            if problem then
                return false, problem
            end
        end
        return true
    end
end

plugin.actions.register("sync", {
    permission = false,
    quiet = true,
    validate = adminOnly(),
    run = function(adminId)
        plugin.emit.player(adminId, "todos:board", { cards = board.cards })
    end
})

plugin.actions.register("save", {
    permission = false,
    quiet = true,
    validate = adminOnly(function(args) return cardProblem(args[1]) end),
    run = function(adminId, args)
        local input = args[1]
        local id = input.id
        if id == nil then
            id = ("c%d"):format(board.next)
            board.next = board.next + 1
        end
        local items = {}
        for i, item in ipairs(input.items) do
            items[i] = { text = item.text, done = item.done }
        end
        local card = {
            id = id,
            title = input.title,
            color = input.color,
            x = input.x,
            y = input.y,
            items = items,
            editedBy = GetPlayerName(adminId),
            editedAt = os.time()
        }
        board.cards[id] = card
        persist()
        plugin.emit.admins("todos:card", card, input.id == nil and adminId or nil)
    end
})

plugin.actions.register("remove", {
    permission = false,
    quiet = true,
    validate = adminOnly(function(args)
        if type(args[1]) ~= "string" or not board.cards[args[1]] then
            return "โน้ตนี้ถูกลบไปแล้ว"
        end
    end),
    run = function(_, args)
        board.cards[args[1]] = nil
        persist()
        plugin.emit.admins("todos:removed", args[1])
    end
})
