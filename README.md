# Official plugins for Moonrift Admin

Plugins for the Moonrift Admin FiveM resource. Each folder under `plugins/` is one plugin.

## Install a plugin

1. Open the admin menu, go to **Plugins**, and press **ติดตั้ง** on the plugin.
2. In the server console, run `ensure <admin resource>`.
3. Press the gear on the plugin to set it up.

| Permission | Allows |
| --- | --- |
| `managePlugins` | See plugins and change their settings |
| `installPlugins` | Install, update and uninstall plugins. Give it to the server owner only |

To install a plugin that is not in this repository, copy its folder into the `storage/plugins/` folder of the admin resource, so you get `<admin resource>/storage/plugins/<id>/`, then run `ensure <admin resource>`.

## Write a plugin

A plugin is a folder under `plugins/<id>/` with a `plugin.json` and any of `server.lua`, `client.lua`, `ui.js` and `ui.css`. It can add server actions, HTTP endpoints, code that runs in each admin's game, and its own page in the admin menu.

See [API.md](API.md) for the files, every `plugin.json` field, the server, client and menu page APIs, and how to publish a plugin in `index.json`. The `mcp` plugin is a working example of a server plugin with an HTTP endpoint and a secret token.
