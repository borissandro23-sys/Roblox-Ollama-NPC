# Roblox Ollama NPC — Gemma 4:12B

NPC for Roblox Studio that talks to a local Ollama model through an authenticated Python bridge. It can wander around the map, follow/approach the player, stop, look at the player, and jump.

## Architecture

Roblox game server → HTTPS tunnel → Python bridge on your PC → Ollama on localhost.

Roblox servers cannot directly access your PC's \`127.0.0.1\`, so the bridge is exposed through a temporary HTTPS tunnel for development. **Do not expose Ollama's port 11434 directly.** The bridge binds to localhost and requires a long random API key.

## Requirements

- Roblox Studio
- Python 3.10+
- Ollama installed and running
- Model available locally (default tag: \`gemma4:12b\`)
- Cloudflare Tunnel (\`cloudflared\`) for a temporary HTTPS URL

## 1. Prepare Ollama

In PowerShell:

\`\`\`powershell
ollama pull gemma4:12b
ollama list
\`\`\`

If your installed model has a different tag, set \`OLLAMA_MODEL\` to the exact name shown by \`ollama list\`.

## 2. Create a bridge API key

Generate a random key:

\`\`\`powershell
py -c "import secrets; print(secrets.token_urlsafe(32))"
\`\`\`

Copy it temporarily. Do not publish it, commit it, or send it to other people.

Set it in the same PowerShell window where you start the bridge:

\`\`\`powershell
$env:OLLAMA_BRIDGE_TOKEN = "PASTE_RANDOM_TOKEN_HERE"
$env:OLLAMA_MODEL = "gemma4:12b"
py .\proxy\server.py
\`\`\`

Expected output includes \`Bridge listening on http://127.0.0.1:8000\`.

Check the local health endpoint in a browser: \`http://127.0.0.1:8000/health\`.

## 3. Create a temporary HTTPS tunnel

In a second PowerShell window:

\`\`\`powershell
cloudflared tunnel --url http://localhost:8000
\`\`\`

Copy the generated \`https://....trycloudflare.com\` address. Quick Tunnels are temporary; the URL changes when the tunnel is restarted. Keep both windows open while testing.

A tunnel URL is public. The API key is required for every chat request. Do not remove authentication or share the key.

## 4. Set up Roblox Studio

1. Open your Roblox place.
2. Add an NPC rig using **Avatar > Rig Builder**.
3. Name the Model exactly \`OllamaNPC\` and put it in \`Workspace\`.
4. Make sure it contains \`Humanoid\`, \`HumanoidRootPart\`, and \`Head\`.
5. In **Game Settings > Security**, enable **Allow HTTP Requests**.
6. Create a Script in \`ServerScriptService\`, name it \`OllamaNPC.server.lua\`, and paste the server script from this repository.
7. In that script, replace \`BRIDGE_URL\` with your current HTTPS tunnel URL.
8. For Studio testing only, replace \`STUDIO_TEST_TOKEN\` with the same random key used by the Python bridge.
9. Create a LocalScript in \`StarterPlayer > StarterPlayerScripts\`, name it \`OllamaNPC.client.lua\`, and paste the client script.

## 5. Secure the published experience

Do not publish the Studio fallback key in a live game.

In Creator Hub, open your experience's **Secrets** page and create a secret:
- Name: \`OLLAMA_TOKEN\`
- Value: the same random key as \`OLLAMA_BRIDGE_TOKEN\`
- Domain: \`*.trycloudflare.com\` for a temporary Quick Tunnel, or the exact hostname of your stable bridge server.

The script reads the key using \`HttpService:GetSecret("OLLAMA_TOKEN")\` and sends it in the \`x-api-key\` header. Roblox Secrets are intended for server-side use. Restart the game server after changing a secret.

For a public production game, use a stable HTTPS hosting service, narrow domain restrictions, monitoring, and a secret rotation plan. A temporary Quick Tunnel is for development only.

## 6. Test

Run the Python bridge and tunnel, then press **Play** in Studio. Walk up to the NPC and use the proximity prompt, or type in chat:

\`\`\`text
!ai привет
!ai иди за мной
!ai остановись
!ai подойди ко мне
!ai снова гуляй
!ai посмотри на меня
!ai подпрыгни
\`\`\`

The NPC also wanders automatically around its starting position.

## 7. Roblox Studio coding agent plugin

The repository also includes a Studio dock-widget plugin powered by the same local Ollama bridge. Unlike the NPC, the plugin runs on your PC inside Studio, so it connects directly to `http://127.0.0.1:8000` — **no Cloudflare tunnel is needed for plugin use**.

### Install

1. Open `plugin/RobloxOllamaAgent.plugin.lua` from this repository.
2. Download the raw Lua file from GitHub.
3. In Roblox Studio, open **Plugins > Manage Plugins** and use the local plugin installation/import option available in your Studio version. If your version does not show that option, place the file in Studio's local Plugins folder and restart Studio.
4. In **Game Settings > Security**, enable **Allow HTTP Requests** for Studio testing.
5. Start the Python bridge as described above. Keep Ollama running.
6. Open the **Ollama AI** toolbar and click **Ollama Agent**.
7. Leave the bridge URL as `http://127.0.0.1:8000`, enter the same API key used by `OLLAMA_BRIDGE_TOKEN`, and select exactly one `Script`, `LocalScript`, or `ModuleScript` in Explorer.
8. Describe the change in Russian and click **Спросить Gemma**.
9. Review the explanation and generated Luau in the preview. Click **Применить к выбранному скрипту** only when you are satisfied.

### What it does

- Sends the selected script's type, name, source and your request to Gemma 4:12B.
- Generates a complete replacement source file, not a partial patch.
- Lets you inspect the proposed code before changing anything.
- Applies code only after you press the Apply button. Studio's undo can revert the edit.
- Keeps the API key in the plugin window for the current Studio session; it is not written into the plugin source or repository.

**Important:** The API key is visible as plain text in the plugin field and is sent only to your local bridge. Do not stream or share the Studio window while the key is entered. Do not put a real key in a game script or commit it to GitHub. The plugin does not execute model-generated code automatically; test changes in a private place and inspect them first.

The agent edits only the one selected script. It does not yet create whole game systems across multiple files, run playtests, or automatically repair Output errors.

## Troubleshooting

- **NPC does not move:** check that the rig has a living Humanoid, an unanchored root part, and a clear walkable floor. Check Output for pathfinding errors.
- **HTTP request fails:** verify Allow HTTP Requests, the tunnel URL, and that both Python and cloudflared windows are running.
- **401 unauthorized:** the key in the Roblox script/Secret must exactly match \`OLLAMA_BRIDGE_TOKEN\`.
- **Ollama error:** run \`ollama list\` and verify \`OLLAMA_MODEL\` matches the installed model tag.
- **No speech bubble:** check that the LocalScript is in StarterPlayerScripts and TextChatService is enabled.

## Notes

- The bridge uses only Python's standard library.
- The bridge limits request size and applies a per-player cooldown.
- NPC speech is filtered with Roblox TextService before being shown to all clients.
- The model proposes an action, but the Roblox server validates it against an allowlist before moving the NPC.
- This is a starter project. Test in a private place before publishing.

## References

- [Roblox in-game HTTP requests](https://create.roblox.com/docs/cloud-services/http-service)
- [Roblox Secrets stores](https://create.roblox.com/docs/cloud-services/secrets)
- [Roblox PathfindingService](https://create.roblox.com/docs/characters/pathfinding)
- [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md)
