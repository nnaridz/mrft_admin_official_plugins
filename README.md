# Official plugins for Moonrift Admin

Plugins for the Moonrift Admin FiveM resource. Each folder under `plugins/` is one plugin.

## Install a plugin

1. Open the admin menu, go to **Plugins**, and press **ติดตั้ง** on the plugin.
2. In the server console, run `refresh`, then `ensure <admin resource>`.
3. Press the gear on the plugin to set it up.

| Permission | Allows |
| --- | --- |
| `managePlugins` | See plugins and change their settings |
| `installPlugins` | Install, update and uninstall plugins. Give it to the server owner only |

To install a plugin that is not in this repository, copy its folder into the `storage/plugins/` folder of the admin resource, so you get `<admin resource>/storage/plugins/<id>/`, then run `refresh` and `ensure <admin resource>`.

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
| `textarea` | string | Multi-line text field |
| `number` | number | Number field |
| `toggle` | boolean | Switch |
| `secret` | 64 hex characters, or `""` before the first generation | Read-only field with Copy and Regenerate |

To add a variable, add one entry to `settings`. To remove one, delete its entry.

A `code` entry shows a read-only block with a Copy button, such as an example config. It is not a variable, so it has no `key` or `default`, only `label`, `value` and an optional `hint`. In `value`, `{{resource}}` becomes the admin resource name and `{{<key>}}` becomes that setting's current value:

```json
{ "type": "code", "label": "Example", "value": "{\n  \"url\": \"http://127.0.0.1:30120/{{resource}}/hello\",\n  \"token\": \"{{token}}\"\n}" }
```

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

`index.json` is the list the Plugins page installs from. Add your plugin there when you add its folder:

```json
{ "id": "example", "files": ["plugin.json", "server.lua"] }
```

`files` lists every file the installer downloads from `plugins/<id>/`. Only `.lua` and `.json` files are allowed, with no subfolders.
