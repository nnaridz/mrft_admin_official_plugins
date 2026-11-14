local myId = GetPlayerServerId(PlayerId())

RegisterNetEvent("todos:board", function(payload)
    plugin.nui.send("board", payload)
end)

RegisterNetEvent("todos:card", function(card, creatorId)
    plugin.nui.send("card", { card = card, mine = creatorId == myId })
end)

RegisterNetEvent("todos:removed", function(id)
    plugin.nui.send("removed", { id = id })
end)

plugin.nui.on("sync", function(_, cb)
    plugin.actions.run("todos.sync")
    cb({})
end)

plugin.nui.on("save", function(card, cb)
    plugin.actions.run("todos.save", card)
    cb({})
end)

plugin.nui.on("remove", function(data, cb)
    plugin.actions.run("todos.remove", data.id)
    cb({})
end)
