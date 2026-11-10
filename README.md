# Official plugins for Moonrift Admin

Plugins for the Moonrift Admin FiveM resource. Each folder under `plugins/` is one plugin.

## Install a plugin

1. Copy the plugin folder into the `plugins/` folder of the admin resource, so you get `<admin resource>/plugins/<id>/`.
2. Restart the server.
3. Open the admin menu, go to **Plugins**, and press the gear on the plugin to set it up.

Only admin groups with the `managePlugins` permission can see and change plugin settings.

## Write a plugin

A plugin is a folder named after its id:

```
plugins/<id>/
  plugin.json    required, describes the plugin and its settings
  server.lua     required, runs on the server after the admin core
```

The admin resource writes `config.json` into the same folder when an admin saves a setting. Do not ship that file.

### plugin.json

```json
{
  "id": "example",
  "name": "Example",
  "version": "1.0.0",
  "author": "You",
  "icon": "puzzle",
  "description": "One line shown in the Plugins page",
  "settings": [
    { "key": "message", "type": "text", "label": "Message", "hint": "Shown on join", "default": "Hello" },
    { "key": "limit", "type": "number", "label": "Limit", "default": 10 },
    { "key": "enabled", "type": "toggle", "label": "Enabled", "default": true },
    { "key": "token", "type": "secret", "label": "Token", "default": "" }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `id` | Must equal the folder name |
| `icon` | A [Lucide](https://lucide.dev/icons) icon name |
| `settings` | The variables an admin can change in the menu. Use `[]` for none |

Every setting needs `key`, `type`, `label` and `default`. `hint` is optional.

| Type | Value | Control in the menu |
| --- | --- | --- |
| `text` | string | Text field |
| `number` | number | Number field |
| `toggle` | boolean | Switch |
| `secret` | 64 hex characters, or `""` before the first generation | Read-only field with Copy and Regenerate |

To add a variable, add one entry to `settings`. To remove one, delete its entry.

### server.lua

Call `Plugin(id)` once. It returns the plugin with its current settings:

```lua
local plugin = Plugin("example")

AddEventHandler("playerJoining", function()
    if plugin.config.enabled then
        print(plugin.config.message)
    end
end)
```

`plugin.config` is updated in place when an admin saves a setting, so read `plugin.config.<key>` at the moment you need the value. A value copied into a local at load time goes stale.

`plugin.manifest` holds the decoded `plugin.json`.

## index.json

`index.json` lists every plugin in this repository with its folder and files. Add your plugin there when you add its folder.
