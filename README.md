# Banter DevTools

Client **mod** for [Banter](https://github.com/Banter-Foundation/Banter): live log tail, render-rate estimate, protocol/API panel, debug shell overlay, and a diagnostics dump you can copy from disk.

This is a **separate** repository. It is not part of the Banter monorepo.

## Clone here (Owl / Black-Birb)

```text
D:\Projects\Project Banter\Banter-DevTools
```

Never put Banter trees on `E:`.

```powershell
cd "D:\Projects\Project Banter"
git clone https://github.com/Banter-Foundation/Banter-DevTools.git
```

## Install into Banter

Banter loads mods from the **data directory**, not from the git clone:

| OS | Mods folder |
| --- | --- |
| Windows | `%LOCALAPPDATA%\Banter\mods\` |
| Linux | `$XDG_DATA_HOME/Banter/mods` or `~/.local/share/Banter/mods` |
| Override | `$env:BANTER_DATA\mods` / `$BANTER_DATA/mods` |

Copy or junction the mod folder so Banter sees `banter.mod.json`:

```powershell
# From the clone root (recommended: directory junction so edits apply live)
New-Item -ItemType Junction `
  -Path "$env:LOCALAPPDATA\Banter\mods\devtools" `
  -Target "D:\Projects\Project Banter\Banter-DevTools"
```

Required layout:

```text
%LOCALAPPDATA%\Banter\mods\devtools\
  banter.mod.json
  main.luau
```

## Enable

1. Start Banter.
2. Open **User Settings → Mods**.
3. Find **DevTools** (`devtools`).
4. Turn **Enabled** on.
5. Allow the permission dialogs. This mod asks for `log`, `storage`, `ui`, `io`, and `os`. The second dialog warns about file and OS access — that is intentional so the mod can write `devtools.log` / `diagnostics.txt` and read `os.clock` / env for the data path.

Unload: turn **Enabled** off. That destroys the Luau state and clears the shell overlay.

## Open the window (F3)

Press **F3** on the main Banter window to toggle the floating **DevTools** window. There is **no** header chrome (`Panel` / `Tail` are not injected into `stage.header.actions`).

Requires a Banter host that paints the `devtools` UI slot (Banter PR that adds that region + F3 toggle). Older hosts ignore the slot and show nothing in-shell — enable a matching Banter build.

When this mod is enabled and emitting `devtools` widgets, F3 opens DevTools instead of the built-in Profiler. With the mod disabled, F3 still toggles Profiler.

## What it does today

Inside the F3 window:

| Control | Action |
| --- | --- |
| **Panel** | Cycle: `log` → `perf` → `proto` → `overlay` → `dump` |
| Status text | Shows the active panel’s readout |
| **Tail / Reset / Note / On·Off / Dump** | Panel action |

### Panels

- **log** — Ring buffer of this mod’s `banter.log` lines, appended to `%LOCALAPPDATA%\Banter\devtools.log` (or `$BANTER_DATA`). **Tail** re-reads the last lines from that file; recent lines list in the window.
- **perf** — Estimated **render callback Hz** from `os.clock` deltas (EMA + peak). This is not Banter UI FPS, CPU%, or RSS.
- **proto** — Shows this mod’s version and Banter API generation (`"banter": "1"`). Host release label / wire `PROTOCOL` are **not** exposed to mods yet.
- **overlay** — Toggles a high-contrast `banter.theme.shell` tint so debug chrome is obvious. Off calls `banter.theme.clear_shell`.
- **dump** — Writes `%LOCALAPPDATA%\Banter\diagnostics.txt` (and stores the same text in mod storage key `last_diagnostics`). There is **no** clipboard host API; open that file to copy.

## Permissions

```json
["log", "storage", "ui", "io", "os"]
```

| Permission | Why |
| --- | --- |
| `log` | Write lines Banter shows on the mod’s Settings card |
| `storage` | Remember panel / overlay; keep last diagnostics blob |
| `ui` | DevTools window widgets + shell overlay colors |
| `io` | Append/tail `devtools.log`, write `diagnostics.txt` |
| `os` | `os.clock` for Hz estimate; `os.getenv` for `BANTER_DATA` / `LOCALAPPDATA` / `XDG_DATA_HOME` |

## Host API gaps (do not invent)

Ask Owl before adding fake `banter.*` host functions. Documented vs injected today (Banter `script.rs` / `ModHost`):

| Wanted for DevTools | Status |
| --- | --- |
| Floating DevTools window + F3 | **Shipped** as ImGui window + `devtools` slot (not a second GLFW OS window). |
| True second GLFW OS window (like Settings) | **Missing.** Current window is in-process Dear ImGui. |
| Generic mod keybind API | **Missing.** F3 is hardcoded on the host for this slot / Profiler. |
| True UI FPS / CPU / process memory | **Missing.** Only `os.clock`-based render Hz. |
| Client/server `version` + `PROTOCOL` | **Missing** on the mod host. Exists on `GET /v1/health` for the app, not for Luau mods. |
| System clipboard (`banter.clipboard` or similar) | **Missing.** Dump writes a file instead. |
| Read Banter’s own debug log stream | **Missing.** Mod can only read files it knows about via `io`. |
| `banter.screen` / `banter.events` / `banter.user` / `banter.shell.set` | Spec’d in `docs/modding/mods.md`, **not injected** for client mods in current `install_api`. |
| Rich widgets (`input_text`, `list`, `begin_child`, …) and painting of other slots | Spec’d; host UI today implements `begin` / `close` / `text` / `button`, and paints **`stage.header.actions`** plus **`devtools`**. |

When Banter grows those APIs, this mod should hook them and drop the file/env workarounds.

## Sibling pattern

Same org layout as [AdamsAddions-Mod](https://github.com/Banter-Foundation/AdamsAddions-Mod): separate public repo under **Banter-Foundation**, MIT, clone under `D:\Projects\Project Banter\`.

## License

MIT — see [LICENSE](LICENSE).
