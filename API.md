# Plugin API

How to write a plugin for Moonrift Admin: the files, `plugin.json`, and the API that the server code, the client code and the menu page each get.

A plugin can have three parts. Each one is optional except `plugin.json`:

| Part | File | Runs | Use it for |
| --- | --- | --- | --- |
| Server | `server.lua` | On the server, once, when the admin resource starts | Actions, HTTP endpoints, reacting to admin events |
| Client | `client.lua` | In the game of each admin who is allowed to use the plugin | Natives that only work on the client, talking to the menu page |
| Menu page | `ui.js`, `ui.css` | In the admin menu of the same admins | A page in the menu sidebar |

Contents:

- [Files](#files)
- [plugin.json](#pluginjson)
- [Server API](#server-api)
- [Client API](#client-api)
- [Menu page API](#menu-page-api)
- [How the three parts talk](#how-the-three-parts-talk)
- [Compatibility with older admin versions](#compatibility-with-older-admin-versions)
- [Publishing in this repository](#publishing-in-this-repository)

## Files

A plugin is one folder named after its id, with no subfolders:

```
plugins/<id>/
  plugin.json    required
  server.lua     optional, always loaded when present
  client.lua     optional, named in plugin.json "client"
  ui.js          optional, named in plugin.json "ui.script"
  ui.css         optional, named in plugin.json "ui.style"
```

On a server the folder lives at `<admin resource>/storage/plugins/<id>/`. The admin resource writes `config.json` there when an admin saves a setting. Do not ship that file.

The id may contain letters, digits, `_` and `-`.

## plugin.json

```json
{
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "author": "You",
  "icon": "puzzle",
  "description": "One line shown in the Plugins page",
  "permission": "example",
  "client": "client.lua",
  "ui": {
    "script": "ui.js",
    "style": "ui.css",
    "page": { "label": "Example", "icon": "box" }
  },
  "settings": [
    { "key": "message", "type": "text", "label": "Message", "hint": "Shown on join", "default": "Hello" }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Must equal the folder name |
| `name`, `version`, `author`, `description` | yes | Shown on the Plugins page. Bump `version` on every change, so servers see the update |
| `icon` | yes | A [Lucide](https://lucide.dev/icons) icon name, shown on the Plugins page |
| `settings` | yes | Values an admin can change in the menu. Use `[]` for none: older admin versions fail to load a plugin without the field |
| `permission` | no | A permission key. When set, only admins whose group has it get the client code and the menu page. Without it, every admin gets them |
| `client` | no | File name of the client code |
| `ui.script`, `ui.style` | no | File names of the menu page code and its styles |
| `ui.page.label`, `ui.page.icon` | no | Sidebar text and Lucide icon for the page. They default to the id and `puzzle` |

A permission key only works once the server owner adds it to the groups in the admin resource's `config.permissions`, for example `["example"] = true`. Say which keys your plugin needs in its description or hint.

### Settings

Every setting needs `key`, `type`, `label` and `default`. `hint` is optional.

| Type | Value | Control in the menu |
| --- | --- | --- |
| `text` | string | Text field |
| `textarea` | string | Multi-line text field |
| `number` | number | Number field |
| `toggle` | boolean | Switch |
| `secret` | 64 hex characters, or `""` before the first generation | Read-only field with Copy and Regenerate |

A `code` entry shows a read-only block with a Copy button, such as an example config. It is not a value, so it has no `key` or `default`, only `label`, `value` and an optional `hint`. In `value`, `{{resource}}` becomes the admin resource name and `{{<key>}}` becomes that setting's current value:

```json
{ "type": "code", "label": "Example", "value": "{\n  \"url\": \"http://127.0.0.1:30120/{{resource}}/example\",\n  \"token\": \"{{token}}\"\n}" }
```

## Server API

`server.lua` calls `Plugin(id)` once, at the top, and keeps the handle:

```lua
local plugin = Plugin("example")
```

### When things are available

`server.lua` runs while the resource loads, before the admin core has started. The handle has two kinds of calls:

- **Registrations** (`actions.register`, `on`, `http.route`) can be made right away, at the top level of the file. They take effect when the core starts.
- **Everything else** (looking up players, banning, sending events) needs the core. Call it from inside a handler: an action, a listener, an HTTP route, an event handler or a thread. Called at load time it raises "is not available until the admin resource has initialized".

Calls that touch the database (`bans.*`) wait for the query, so they must run inside a handler or a thread. FiveM event handlers and the handlers above already are.

### Reference

| Call | Returns | What it does |
| --- | --- | --- |
| `plugin.id` | string | The plugin id |
| `plugin.manifest` | table | The decoded `plugin.json` |
| `plugin.config.<key>` | value | A setting's current value. Updated in place when an admin saves, so read it when you need it. A copy taken at load time goes stale |
| `plugin.settings.get(key)` | value | Same as `plugin.config[key]` |
| `plugin.settings.set(key, value)` | | Saves a setting from code. Errors if the value does not fit the setting's type |
| `plugin.actions.register(name, spec)` | | Adds a server action, see [Actions](#actions) |
| `plugin.actions.run(adminId, name, ...)` | | Runs any action by its full name, as that admin. `adminId` 0 runs it as the console and skips the permission check |
| `plugin.on(listenerName, fn)` | | Calls `fn` on an admin event, see [Listeners](#listeners) |
| `plugin.http.route(method, path, fn)` | | Answers HTTP requests, see [HTTP routes](#http-routes) |
| `plugin.emit.admins(event, ...)` | | Triggers a client event for every online admin |
| `plugin.emit.player(target, event, ...)` | | Triggers a client event for one server id, or for a list of ids |
| `plugin.hasPermission(playerId, key)` | boolean | Whether that player's group has the permission key |
| `plugin.log(playerId, channel, message)` | | Sends `message` to a webhook channel from the admin's `config/server.webhook.lua`, such as `"DefaultAction"` or `"DangerAction"` |
| `plugin.players.list()` | table | Online players by server id: `{ name, identifier, discord, profile, group }` |
| `plugin.players.get(serverId)` | table or nil | One entry of `players.list()` |
| `plugin.players.admins()` | table | Online admins: server id → group |
| `plugin.bans.add(adminId, targetId, identifier, reason, duration)` | | Bans an online player (`targetId`), or an identifier while they are offline (`targetId` nil). `duration` is `"forever"` or a number and a unit: `"12h"`, `"3d"`, `"1m"` (30 days), `"1y"`. Kicks the player, tells admins, writes the webhook |
| `plugin.bans.remove(adminId, identifier)` | boolean | Lifts a ban. True if one was removed |
| `plugin.bans.find(identifier)` | table or nil | The active ban on that identifier: `{ identifier, name, reason, banned_at, expires_at }`. Times are unix seconds, and `expires_at` is nil for a permanent ban |
| `plugin.reports.list()` | array | Open reports: `{ caseId, playerId, name, profile, message, category, category_label, coords, screenshot_url, date }` |

### Actions

An action is something an admin triggers that runs on the server. The admin core checks the permission, logs it and fires the `onAction` listener, so your code only does the work.

```lua
plugin.actions.register("heal", {
    permission = "example",         -- required
    log = "DefaultAction",          -- optional webhook channel
    validate = function(adminId, args)
        if not GetPlayerName(args[1]) then
            return false, "Player is not online"
        end
        return true
    end,
    run = function(adminId, args)
        TriggerClientEvent("example:heal", args[1])
        return ("healed player %s"):format(args[1])   -- logged with the admin's name in front
    end
})
```

The action is registered as `<id>.<name>`, here `example.heal`. Run it from the plugin's client code with `plugin.actions.run("example.heal", targetId)`.

| Spec field | Required | Meaning |
| --- | --- | --- |
| `permission` | yes | A permission key, `false` for no check, or `function(adminId, args) return key end` to pick one per call |
| `run(adminId, args)` | yes | The work. `args` is the list of arguments the client sent. A returned string is the log text |
| `validate(adminId, args)` | no | Return `true`, or `false, message`. The message is shown to the admin and `run` is skipped |
| `log` | no | Webhook channel for the text `run` returns |
| `quiet` | no | `true` skips the `onAction` listener, for calls that are not admin decisions, such as a page refresh |

Check every argument in `validate` or `run`. The client is the player's own game, so treat `args` as untrusted input.

### Listeners

`plugin.on(name, fn)` runs `fn` after the admin event `name`, with the same arguments the admin's `config/listener/listener.server.lua` gets. Each call runs in its own thread, and an error in your handler does not affect the admin action.

```lua
plugin.on("onBan", function(adminId, targetId, identifier, reason, duration)
    print(("ban by %s on %s: %s"):format(adminId, identifier, reason))
end)
```

| Name | Arguments |
| --- | --- |
| `onAction` | adminId, action, args |
| `onAnnouncement` | adminId, message |
| `onSetWeather` | adminId, weather |
| `onSetTime` | adminId, hour, minute |
| `onFreezeTime`, `onFreezeWeather` | adminId, state |
| `onGive` | adminId, targetId, items |
| `onGiveAll` | adminId, items, includeOffline |
| `onClearItems`, `onClearWeapons` | adminId, targetId, identifier |
| `onSetGroup` | adminId, targetId, group |
| `onSetJob` | adminId, targetId, jobName, jobGrade |
| `onGoto`, `onBring`, `onSpectate` | adminId, targetId |
| `onResetCharacter` | adminId, targetId, identifier |
| `onKick` | adminId, targetId, reason |
| `onBan` | adminId, targetId, identifier, reason, duration |
| `onBanInput` | adminId, typedInput, reason, duration |
| `onRevokeBan` | adminId, identifier, removed |
| `onExecuteCode` | adminId, option, code, targetIds |
| `onAddonAction` | adminId, addon, state |
| `onPlayerAddonAction` | adminId, addon, targetId |
| `onPlayerBlipsToggle`, `onLiveMapToggle` | adminId, state |
| `onReportCreated` | playerId, report |
| `onReportSolved` | adminId, caseId |
| `onReportGoto` | adminId, caseId, report |
| `onRequestScreen` | adminId, targetId |
| `onDeleteAllVehicles`, `onDeleteAllProps` | adminId |
| `onDeleteNearbyVehicles`, `onDeleteNearbyProps` | adminId, radius |

`onAction` fires for every action that is not `quiet`, including plugin actions.

### HTTP routes

The admin resource owns the HTTP handler and passes each request to the plugin whose id starts the path. A plugin answers only under its own id:

```
http://<server>:30120/<admin resource>/<id><path>
```

```lua
-- http://127.0.0.1:30120/<admin resource>/example
plugin.http.route("GET", "/", function(req, res)
    res.writeHead(200, { ["Content-Type"] = "application/json" })
    res.send(json.encode({ players = GetNumPlayerIndices() }))
end)

-- http://127.0.0.1:30120/<admin resource>/example/status, any method
plugin.http.route("*", "/status", function(req, res) ... end)
```

- `method` is `"GET"`, `"POST"` and so on, or `"*"` for any. A route for one method does not answer other methods; use `"*"` and check `req.method` to send a 405 yourself.
- `path` is matched exactly, without the query string.
- `req` and `res` are the request and response objects of FiveM's `SetHttpHandler`: `req.path`, `req.method`, `req.headers`, `res.writeHead(status, headers)`, `res.send(body)`. Read a body with `req.setDataHandler(function(body) ... end)`.
- An unmatched request gets a 404.
- Anyone who can reach the server's port can call a route. Check a token: a `secret` setting is made for this, see the `mcp` plugin.

Do not call `SetHttpHandler` yourself. It still works for one old-style plugin, but it receives every request no plugin route matches.

## Client API

`client.lua` runs in the game of each admin who gets the plugin (see `permission` in [plugin.json](#pluginjson)), after their admin menu has loaded. Players who are not admins never receive plugin code.

The file runs in its own environment: it can read every global and call every native, and the globals it creates stay private to the plugin. It gets one extra global, `plugin`:

| Call | What it does |
| --- | --- |
| `plugin.id` | The plugin id |
| `plugin.nui.send(event, data)` | Sends `data` to the plugin's menu page, received by `ctx.on(event, fn)` |
| `plugin.nui.on(name, fn)` | Answers `ctx.nui(name, data)` from the menu page. `fn(data, cb)` must call `cb(result)` exactly once, or the page waits forever |
| `plugin.actions.run(name, ...)` | Runs a server action by its full name: `"example.heal"` for your own, or a core action such as `"goto"` |
| `plugin.notify(message, duration, kind)` | Shows a toast. `kind` is `"info"`, `"success"`, `"warning"` or `"error"` |
| `plugin.hasPermission(key)` | Whether this admin's group has the permission key. Use it to hide things, never as the only check: the server checks again |
| `plugin.closeMenu()` | Closes the admin menu, for tools that need the game view |

```lua
plugin.nui.on("heal", function(data, cb)
    plugin.actions.run("example.heal", data.target)
    cb({ ok = true })
end)

RegisterCommand("example", function()
    plugin.nui.send("hello", { time = GetGameTimer() })
end, false)
```

## Menu page API

`ui.js` is an ES module that runs in the admin menu. Its default export is a function, which the menu calls once with a context:

```js
export default (ctx) => {
  ctx.page({
    mount($host) {
      const $count = $('<span>', { text: '-' });
      $host.append(
        $('<div>', { class: 'example-row' }).append(
          $count,
          ctx.ui.iconTextButton('heart', 'Heal player 1', 'primary', () => {
            ctx.nui('heal', { target: 1 }).then((result) => ctx.ui.toast(result.ok ? 'Healed' : 'Failed', 3000, 'info'));
          })
        )
      );
      ctx.on('hello', (data) => $count.text(data.time));
    }
  });
};
```

| Context | What it does |
| --- | --- |
| `ctx.id` | The plugin id |
| `ctx.page({ mount($host) })` | Adds the sidebar entry from `plugin.json` `ui.page` and a page. `mount` runs the first time the page opens; `$host` is the page's empty element (jQuery). Call `page` at most once |
| `ctx.nui(name, data)` | Calls the client handler `plugin.nui.on(name)`. Returns a jQuery promise of what the handler passed to `cb` |
| `ctx.on(event, fn)` | Runs `fn(data)` for each `plugin.nui.send(event, data)` from the client |
| `ctx.ui` | The admin menu's own building blocks, below |

Use `ctx.ui` so the page looks like the rest of the menu. All of these return jQuery elements unless noted:

| Helper | Arguments |
| --- | --- |
| `button` | `(text, variant, onClick)`. `variant` is `''`, `'primary'` or `'danger'` |
| `iconButton` | `(iconName, title, onClick)` |
| `iconTextButton` | `(iconName, text, variant, onClick)` |
| `textField` | `(value, placeholder, type = 'text')` |
| `formField` | `(label, control, className)`: a label above a control |
| `segmented` | `(options, active, onChange)`. `options` is `[[value, text], ...]` |
| `dropdown` | `(options, value, onChange)`. Same `options` shape |
| `searchField` | `(placeholder, onInput)` |
| `emptyState` | `(iconName, text)`: a centered icon and line of text |
| `icon` | `(name)`: a Lucide icon |
| `toast` | `(message, duration, type)`. Nothing returned |
| `modal` | `({ title, subtitle, description, body, foot, size })`. `body` and `foot` are arrays of elements |
| `closeModal` | `()` |
| `confirmModal` | `({ title, description, onConfirm })` |
| `promptModal` | `({ title, description, type, placeholder, value, onConfirm(value) })` |
| `copyToClipboard` | `(text)` |
| `denied` | `(permissionKey)`: true when this admin's group lacks the key |
| `locale` | `(key)`: a text from the admin's locale file |

`ui.css` is added to the whole menu, so start every selector with a class of your own, such as `.example-row`, so you do not restyle the core pages. jQuery (`$`) is available.

Because `ui.js` is a module, it runs in strict mode and its top-level variables stay private to the plugin. It must be a single file: the menu loads it from text, so it cannot `import` other files of the plugin.

If `ui.js` fails to load, throws, or has no default export, the menu shows a "plugin failed to load" toast and the other plugins still load. Open the NUI devtools (`nui_devtools` in the F8 console) to see the error; it points at `plugin/<id>/ui.js`.

## How the three parts talk

```
menu page (ui.js)        client (client.lua)              server (server.lua)
ctx.nui('heal', d)  -->  plugin.nui.on('heal', fn)
                         plugin.actions.run(              plugin.actions.register(
                           'example.heal', id)      -->     'heal', { run = ... })
ctx.on('hello', fn) <--  plugin.nui.send('hello', d)
                         RegisterNetEvent(...)      <--   plugin.emit.player(id, event, ...)
```

- Page to client: `ctx.nui` → `plugin.nui.on`, which answers through `cb`.
- Client to page: `plugin.nui.send` → `ctx.on`.
- Client to server: `plugin.actions.run`. The permission check, logging and listeners come with it. A plain `TriggerServerEvent` works too, but then you check permissions yourself.
- Server to client: `plugin.emit.admins` or `plugin.emit.player`, received with `RegisterNetEvent` in `client.lua`. Prefix event names with your id, such as `example:heal`.

## Compatibility with older admin versions

`plugin.http`, `plugin.actions`, `plugin.on` and the other server calls above, plus `client.lua` and the menu page, need an admin resource with plugin API v2. On an older admin `Plugin(id)` only has `id`, `manifest` and `config`, `client` and `ui` in `plugin.json` are ignored, and `settings` must be present.

To support both, check for the field, as the `mcp` plugin does:

```lua
if plugin.http then
    plugin.http.route("*", "/", handle)
else
    SetHttpHandler(function(req, res) ... end)
end
```

## Publishing in this repository

Add the folder under `plugins/` and an entry to `index.json`, which is the list the Plugins page installs from:

```json
{ "id": "example", "files": ["plugin.json", "server.lua", "client.lua", "ui.js", "ui.css"] }
```

`files` lists every file the installer downloads from `plugins/<id>/`. Allowed types are `.lua`, `.json`, `.js` and `.css`, with no subfolders.

Older admin versions only accept `.lua` and `.json`, and they reject the whole list if any entry has another type, so their Plugins page would show no plugins at all. Until the servers using this repository run plugin API v2, keep `.js` and `.css` files out of `index.json`.
