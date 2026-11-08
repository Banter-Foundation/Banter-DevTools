-- Banter DevTools v1.1.0
-- Client mod. Uses only host APIs that Banter actually injects today.
-- UI lives in the floating `devtools` window (F3). No stage.header.actions chrome.
-- Gaps (host FPS/CPU/mem, protocol, clipboard, screen APIs, second GLFW OS window,
-- generic keybind API) are documented in README.md.

local MOD_VERSION = "1.1.0"
local BANTER_API = "1"
local LOG_CAP = 80
local TAIL_BYTES = 6000
local LOG_LINES_SHOWN = 12

local panels = { "log", "perf", "proto", "overlay", "dump" }
local panel = "log"
local overlay_on = false
local status = "ready"
local logs = {}
local last_clock = nil
local sample_hz = 0
local peak_hz = 0
local frame_n = 0
local last_tail_at = 0
local tailed_line = ""
local data_dir = nil
local log_path = nil
local dump_path = nil

local function push_log(level, message)
	local line = level .. " " .. message
	table.insert(logs, line)
	while #logs > LOG_CAP do
		table.remove(logs, 1)
	end
	banter.log(level, message)
	if log_path and io and io.open then
		local file = io.open(log_path, "a")
		if file then
			file:write(line .. "\n")
			file:close()
		end
	end
end

local function resolve_data_dir()
	if not os or not os.getenv then
		return nil
	end
	local from_env = os.getenv("BANTER_DATA")
	if from_env and from_env ~= "" then
		return from_env
	end
	local local_app = os.getenv("LOCALAPPDATA")
	if local_app and local_app ~= "" then
		return local_app .. "\\Banter"
	end
	local xdg = os.getenv("XDG_DATA_HOME")
	if xdg and xdg ~= "" then
		return xdg .. "/Banter"
	end
	local home = os.getenv("HOME")
	if home and home ~= "" then
		return home .. "/.local/share/Banter"
	end
	return nil
end

local function load_prefs()
	local saved_panel = banter.storage.get("panel")
	if saved_panel then
		for _, name in ipairs(panels) do
			if name == saved_panel then
				panel = saved_panel
				break
			end
		end
	end
	local saved_overlay = banter.storage.get("overlay")
	overlay_on = saved_overlay == "1"
end

local function save_prefs()
	banter.storage.set("panel", panel)
	banter.storage.set("overlay", overlay_on and "1" or "0")
end

local function apply_overlay()
	if not banter.theme then
		return
	end
	if overlay_on then
		-- High-contrast debug tint using the real theme.shell API (no invented overlay host).
		banter.theme.shell({
			rail_bg = 0x2A1A00,
			sidebar_bg = 0x332200,
			stage_bg = 0x1A1400,
			panel_bg = 0x2A2200,
			composer_bg = 0x2A2200,
			accent = 0xFFB020,
			danger = 0xFF5A5A,
		})
	else
		banter.theme.clear_shell()
	end
end

local function cycle_panel()
	local index = 1
	for i, name in ipairs(panels) do
		if name == panel then
			index = i
			break
		end
	end
	panel = panels[(index % #panels) + 1]
	save_prefs()
	push_log("info", "panel " .. panel)
end

local function toggle_overlay()
	overlay_on = not overlay_on
	save_prefs()
	apply_overlay()
	status = overlay_on and "overlay on" or "overlay off"
	push_log("info", status)
end

local function tail_log_file()
	if not log_path or not io or not io.open then
		tailed_line = "(io unavailable)"
		return
	end
	local file = io.open(log_path, "r")
	if not file then
		tailed_line = "(no log file yet)"
		return
	end
	local text = file:read("*a")
	file:close()
	if type(text) ~= "string" or text == "" then
		tailed_line = "(empty log)"
		return
	end
	if #text > TAIL_BYTES then
		text = string.sub(text, #text - TAIL_BYTES + 1)
	end
	local last = ""
	for line in string.gmatch(text, "[^\r\n]+") do
		last = line
	end
	tailed_line = last
end

local function write_diagnostics()
	if not dump_path or not io or not io.open then
		status = "dump failed: no io"
		push_log("error", status)
		return
	end
	local lines = {
		"Banter DevTools diagnostics",
		"mod_version=" .. MOD_VERSION,
		"banter_api=" .. BANTER_API,
		"panel=" .. panel,
		"overlay=" .. (overlay_on and "on" or "off"),
		"sample_hz=" .. string.format("%.1f", sample_hz),
		"peak_hz=" .. string.format("%.1f", peak_hz),
		"data_dir=" .. (data_dir or "(unknown)"),
		"log_path=" .. (log_path or "(unknown)"),
		"host_gaps=no FPS/CPU/mem API; no protocol/version API; no clipboard API; banter.screen/events/user not injected for mods; no second GLFW OS window or generic keybind API for mods",
		"---- recent log ----",
	}
	for _, line in ipairs(logs) do
		table.insert(lines, line)
	end
	local body = table.concat(lines, "\n") .. "\n"
	local file = io.open(dump_path, "w")
	if not file then
		status = "dump failed: open"
		push_log("error", status)
		return
	end
	file:write(body)
	file:close()
	-- Also keep a copy in mod storage (survives restart; user can copy from Settings / file).
	banter.storage.set("last_diagnostics", body)
	status = "wrote diagnostics.txt"
	push_log("info", status .. " -> " .. dump_path)
end

local function sample_perf()
	if not os or not os.clock then
		return
	end
	local now = os.clock()
	if type(now) ~= "number" then
		return
	end
	if last_clock then
		local dt = now - last_clock
		if dt > 0 then
			local hz = 1 / dt
			-- EMA so the window stays readable.
			if sample_hz <= 0 then
				sample_hz = hz
			else
				sample_hz = sample_hz * 0.9 + hz * 0.1
			end
			if hz > peak_hz then
				peak_hz = hz
			end
		end
	end
	last_clock = now
end

local function panel_label()
	if panel == "log" then
		local latest = logs[#logs] or tailed_line or "(quiet)"
		if #latest > 72 then
			latest = string.sub(latest, 1, 69) .. "..."
		end
		return latest
	elseif panel == "perf" then
		return string.format("Hz %.0f peak %.0f", sample_hz, peak_hz)
	elseif panel == "proto" then
		return "api " .. BANTER_API .. " mod " .. MOD_VERSION
	elseif panel == "overlay" then
		return overlay_on and "overlay ON" or "overlay OFF"
	elseif panel == "dump" then
		return status
	end
	return panel
end

local function panel_action()
	if panel == "log" then
		tail_log_file()
		status = "tailed log"
		push_log("debug", "tail refresh")
	elseif panel == "perf" then
		peak_hz = sample_hz
		status = "peak reset to current"
		push_log("info", status)
	elseif panel == "proto" then
		status = "no host version API"
		push_log("warn", "host protocol/version not exposed to mods")
	elseif panel == "overlay" then
		toggle_overlay()
	elseif panel == "dump" then
		write_diagnostics()
	end
end

local function action_label()
	if panel == "overlay" then
		return overlay_on and "Off" or "On"
	elseif panel == "dump" then
		return "Dump"
	elseif panel == "log" then
		return "Tail"
	elseif panel == "perf" then
		return "Reset"
	elseif panel == "proto" then
		return "Note"
	end
	return "Do"
end

local function draw_log_lines()
	local start = math.max(1, #logs - LOG_LINES_SHOWN + 1)
	if #logs == 0 then
		banter.ui.text(tailed_line ~= "" and tailed_line or "(quiet)", "muted")
		return
	end
	for i = start, #logs do
		local line = logs[i]
		if #line > 78 then
			line = string.sub(line, 1, 75) .. "..."
		end
		banter.ui.text(line, "muted")
	end
end

-- Boot
load_prefs()
data_dir = resolve_data_dir()
if data_dir then
	-- Files live next to other Banter data so Owl can find them without a clipboard API.
	local sep = string.find(data_dir, "\\") and "\\" or "/"
	log_path = data_dir .. sep .. "devtools.log"
	dump_path = data_dir .. sep .. "diagnostics.txt"
end
apply_overlay()
push_log("info", "DevTools " .. MOD_VERSION .. " loaded")
if data_dir then
	push_log("info", "data " .. data_dir)
else
	push_log("warn", "could not resolve Banter data dir")
end
push_log("info", "press F3 to toggle the DevTools window")

banter.render(function()
	frame_n = frame_n + 1
	sample_perf()

	-- Throttle file tail so we stay under the process-rate lock.
	if os and os.clock then
		local now = os.clock()
		if type(now) == "number" and now - last_tail_at > 0.5 then
			last_tail_at = now
			if panel == "log" then
				tail_log_file()
			end
		end
	end

	-- Floating DevTools window (host paints this slot; F3 toggles). No header chrome.
	if banter.ui.begin("devtools") then
		banter.ui.text("panel: " .. panel, "heading")
		if banter.ui.button("Panel") then
			cycle_panel()
		end
		banter.ui.text(panel_label(), "body")
		if banter.ui.button(action_label()) then
			panel_action()
		end
		if panel == "log" then
			banter.ui.text("recent", "muted")
			draw_log_lines()
		elseif panel == "perf" then
			banter.ui.text("render-callback Hz from os.clock (not UI FPS)", "muted")
		elseif panel == "proto" then
			banter.ui.text("host release / PROTOCOL not exposed to mods", "muted")
		elseif panel == "overlay" then
			banter.ui.text("tints Banter shell via banter.theme.shell", "muted")
		elseif panel == "dump" then
			banter.ui.text(dump_path or "(no dump path)", "muted")
		end
		banter.ui.text(status, "muted")
		banter.ui.close()
	end
end)
