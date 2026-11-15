RegisterNetEvent("activity:history", function(entries)
    plugin.nui.send("history", { entries = entries })
end)

RegisterNetEvent("activity:entry", function(entry)
    plugin.nui.send("entry", entry)
end)

plugin.nui.on("sync", function(_, cb)
    plugin.actions.run("activity.sync")
    cb({})
end)
