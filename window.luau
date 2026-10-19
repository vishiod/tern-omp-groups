-- omp-groups, window half: moves omp chats into the Tern session of their group code, and adds
-- the "Reopen omp chat" and "Read omp chat history" palette commands.
local codes = require("./codes")
local transcript = require("./transcript")

local HOME = tern.getenv("HOME") or ""
local SESSIONS_DIR = HOME .. "/.omp/agent/sessions"
local HISTORY_DB = HOME .. "/.omp/agent/history.db"
-- A history note keeps the newest messages that fit in this size.
local HISTORY_MAX_BYTES = 512 * 1024
-- Tern turns off a hook that runs over 50 ms, so a long session file is read in slices of this
-- many milliseconds, one timer callback each.
local HISTORY_SLICE_MS = 15

local function fail(cx, what: string, reason: any)
	cx:toast("error", what, tostring(reason))
end

-- Moved list: pane id (as text) -> code. A pane in it never moves again.
local function moved(): { [string]: string }
	return tern.kv.get("moved") or {}
end

-- Records `pane` as moved and drops entries of panes that no longer exist.
-- (Tern sends no `pane_closed` for panes closed through the CLI, so pruning happens here.)
local function set_moved(cx, pane: number, code: string)
	local list: { [string]: string } = {}
	for key, value in moved() do
		local id = tonumber(key)
		if id and cx.session:pane(id) ~= nil then
			list[key] = value
		end
	end
	list[tostring(pane)] = code
	tern.kv.set("moved", list)
end

local function session_named(cx, name: string)
	for _, s in cx.session:sessions() do
		if s.name == name then
			return s
		end
	end
	return nil
end

local function session_of(cx, pane: number)
	local tab = cx.session:tab_of(pane)
	if tab == nil then
		return nil
	end
	for _, s in cx.session:sessions() do
		for _, t in s.tabs do
			if t == tab then
				return s
			end
		end
	end
	return nil
end

-- The session named `code`, created when missing. Returns its id and, for a new session,
-- the starter shell pane the caller closes once its own tab is in place.
local function ensure_session(cx, code: string, cwd: string?): (number, number?)
	local existing = session_named(cx, code)
	if existing then
		return existing.id, nil
	end
	local created = cx.sessions:create({ name = code, cwd = if cwd ~= "" then cwd else nil })
	local made = session_named(cx, code)
	local first_tab = made and made.tabs[1]
	local starter = nil
	for _, p in cx.session:panes() do
		if first_tab ~= nil and p.tab == first_tab then
			starter = p.pane
			break
		end
	end
	return created.id, starter
end

local function move_chat(cx, pane: number, code: string)
	local info = cx.session:pane(pane)
	local sid, starter = ensure_session(cx, code, info and info.cwd)
	local tab, err = cx.layout:move_to_new_tab(pane, sid)
	if tab == nil then
		error(`move to session {code} failed: {err}`)
	end
	if starter then
		cx.layout:close(starter)
	end
	cx.sessions:switch(sid)
	cx.layout:focus(pane)
end

-- One open history.db connection for this VM.
local db_handle: number? = nil

local function with_db(cx, fn: (db: number, cx: any) -> ())
	if db_handle then
		fn(db_handle, cx)
		return
	end
	cx.db:open(HISTORY_DB):next(function(db, err, cx2)
		if err then
			fail(cx2, "omp-groups: cannot open history.db", err)
			return
		end
		db_handle = db
		fn(db, cx2)
	end)
end

local function sql_text(s: string): string
	return "'" .. string.gsub(s, "'", "''") .. "'"
end

-- One source of truth: a chat's group is the Tern session that holds it. The plugin stores the
-- last known session per omp chat id (kv `groups`), so a closed chat keeps the group it had.
local remembered: { [number]: string } = {} -- pane -> "session|title" already stored

local function remember_group(cx, pane: number, retry: boolean)
	local info = cx.session:pane(pane)
	local s = session_of(cx, pane)
	if info == nil or s == nil or codes.parse(info.title or "") == nil then
		return
	end
	local name, title = s.name, info.title
	local key = name .. "|" .. title
	if remembered[pane] == key then
		return
	end
	remembered[pane] = key
	with_db(cx, function(db, cx2)
		local sql = `SELECT session_id FROM session_titles WHERE title = {sql_text(title)}`
		cx2.db:query(db, sql, { limit = 5 }):next(function(res, err, cx3)
			if err then
				remembered[pane] = nil
				fail(cx3, "omp-groups: cannot read chat titles", err)
				return
			end
			if #res.rows == 0 then
				-- omp may index a new title a moment after the terminal shows it.
				remembered[pane] = nil
				if retry then
					tern.timer(3000, function(cx4)
						if cx4 then
							remember_group(cx4, pane, false)
						end
					end)
				end
				return
			end
			local groups = tern.kv.get("groups") or {}
			for _, row in res.rows do
				if type(row[1]) == "string" then
					groups[row[1]] = name
				end
			end
			tern.kv.set("groups", groups)
		end)
	end)
end

local function on_title(ev, cx)
	local raw = codes.parse(ev.title)
	if raw == nil then
		return
	end
	if moved()[tostring(ev.pane)] == nil then
		local code = codes.normalize(raw)
		local current = session_of(cx, ev.pane)
		if current == nil then
			return -- parked or not in this window
		end
		if current.name ~= code then
			local ok, err = pcall(move_chat, cx, ev.pane, code)
			if not ok then
				fail(cx, `omp-groups: could not move chat to {code}`, err)
				return
			end
		end
		set_moved(cx, ev.pane, code)
	end
	remember_group(cx, ev.pane, true)
end

-- On window start, every chat that already shows a code counts as moved, so starting moves nothing.
-- A plugin reload keeps the stored list.
local function on_window_start(cx)
	local list: { [string]: string } = {}
	for _, p in cx.session:panes() do
		local raw = codes.parse(p.title or "")
		if raw then
			list[tostring(p.pane)] = codes.normalize(raw)
		end
	end
	tern.kv.set("moved", list)
end

-- A saved chat: its project folder label, its session file and, when omp made one, the folder
-- that holds its subagents.
type ChatFile = { label: string, file: string, dir: string? }

-- Saved chat files by omp chat id.
local function chat_files(): { [string]: ChatFile }
	local files: { [string]: ChatFile } = {}
	for _, bucket in tern.fs.list(SESSIONS_DIR) do
		local ok, names = pcall(tern.fs.list, `{SESSIONS_DIR}/{bucket}`)
		if ok then
			local label = string.gsub(string.gsub(bucket, "^%-+", ""), "%-+$", "")
			local present: { [string]: boolean } = {}
			for _, name in names do
				present[name] = true
			end
			for _, name in names do
				local id = string.match(name, "_([%w%-]+)%.jsonl$")
				if id then
					local stem = string.sub(name, 1, -7)
					local base = `{SESSIONS_DIR}/{bucket}/{stem}`
					files[id] = { label = label, file = base .. ".jsonl", dir = if present[stem] then base else nil }
				end
			end
		end
	end
	return files
end

-- Opens a scrollable note with the user and assistant messages of a chat or subagent.
local function show_history(cx, item)
	local text = tern.fs.read(item.file)
	local entries = {}
	local pos = 1
	local function step(cx2)
		local started = tern.now()
		while pos <= #text do
			local stop = (string.find(text, "\n", pos, true) or (#text + 1)) - 1
			-- Only the start of a line says what it holds, so a tool result is never copied.
			if transcript.wanted(string.sub(text, pos, math.min(stop, pos + 399))) then
				local ok, entry = pcall(tern.json.decode, string.sub(text, pos, stop))
				if ok then
					table.insert(entries, entry)
				end
			end
			pos = stop + 2
			if pos <= #text and tern.now() - started > HISTORY_SLICE_MS then
				tern.timer(0, function(cx3)
					if cx3 then
						local ok, err = pcall(step, cx3)
						if not ok then
							fail(cx3, "omp-groups: could not read history", err)
						end
					end
				end)
				return
			end
		end
		local body, count = transcript.markdown(entries, HISTORY_MAX_BYTES)
		cx2.docs:new_note(item.name, `_{count} messages · {item.file}_\n\n{body}`)
	end
	step(cx)
end

local function open_chat(cx, item)
	if item.pane then
		local s = session_of(cx, item.pane)
		if s then
			cx.sessions:switch(s.id)
		end
		cx.layout:focus(item.pane)
		return
	end
	local sid, starter = ensure_session(cx, item.code, nil)
	cx.sessions:switch(sid)
	local pane = cx.layout:new_tab({ command = `omp --resume {item.id}` })
	if pane == nil then
		error("could not open a tab")
	end
	if starter then
		cx.layout:close(starter)
	end
end

-- mode "open": a chat row opens the chat and an agent row opens its history.
-- mode "history": every row opens its history.
local function show_picker(cx, rows, mode: string)
	local files = chat_files()
	local open: { [string]: number } = {}
	for _, p in cx.session:panes() do
		if p.title and p.title ~= "" then
			open[p.title] = p.pane
		end
	end
	local groups = tern.kv.get("groups") or {}
	local chats = {}
	for _, row in rows do
		local id, title, updated = row[1], row[2], row[3]
		local file = if type(id) == "string" then files[id] else nil
		if file and type(title) == "string" then
			local pane = open[title]
			local live = if pane then session_of(cx, pane) else nil
			table.insert(chats, {
				id = id,
				title = title,
				updated = tonumber(updated) or 0,
				file = file,
				group = if live then live.name else groups[id],
			})
		end
	end
	if #chats == 0 then
		cx:toast("info", "No saved omp chats found")
		return
	end
	local now = os.time()
	local items = {}
	for _, group in codes.group_chats(chats) do
		for _, chat in group.chats do
			local name = codes.strip(chat.title)
			table.insert(items, {
				label = name,
				detail = `{codes.age(now - chat.updated)} · {chat.file.label}`,
				group = group.code,
				current = open[chat.title] ~= nil,
				kind = "chat",
				id = chat.id,
				code = group.code,
				pane = open[chat.title],
				name = name,
				file = chat.file.file,
			})
			if chat.file.dir then
				for _, agent in transcript.agents(chat.file.dir, tern.fs.list) do
					table.insert(items, {
						label = `{string.rep("  ", agent.depth + 1)}↳ {agent.name}`,
						detail = "agent · history",
						group = group.code,
						kind = "agent",
						name = agent.name,
						file = agent.file,
					})
				end
			end
		end
	end
	local opts = if mode == "history"
		then { items = items, placeholder = "Read omp chat history", action = "read" }
		else { items = items, placeholder = "Reopen omp chat or agent", action = "open" }
	cx:pick(opts):next(function(item, err, cx2)
		if err then
			fail(cx2, "omp-groups: picker failed", err)
		elseif item then
			local run = if mode == "history" or item.kind == "agent" then show_history else open_chat
			local ok, e = pcall(run, cx2, item)
			if not ok then
				fail(cx2, "omp-groups: could not open chat", e)
			end
		end
	end)
end

local function list_chats(cx, mode: string)
	with_db(cx, function(db, cx2)
		cx2.db
			:query(db, "SELECT session_id, title, updated_at FROM session_titles ORDER BY updated_at DESC", { limit = 1000 })
			:next(function(res, err, cx3)
				if err then
					fail(cx3, "omp-groups: cannot read chat titles", err)
					return
				end
				local ok, e = pcall(show_picker, cx3, res.rows, mode)
				if not ok then
					fail(cx3, "omp-groups: cannot list chats", e)
				end
			end)
	end)
end

tern.on("window_start", on_window_start)
tern.on("title", on_title)
tern.on("focus", function(ev, cx)
	remember_group(cx, ev.pane, false)
end)
tern.command({
	id = "reopen",
	title = "Reopen omp chat",
	group = "omp",
	run = function(cx)
		list_chats(cx, "open")
	end,
})
tern.command({
	id = "history",
	title = "Read omp chat history",
	group = "omp",
	run = function(cx)
		list_chats(cx, "history")
	end,
})
-- ⌘⇧O belongs to Tern's key preset, so the default chord is ⌘⌥O.
tern.bind("cmd+alt+o", "plugin.omp-groups.reopen")
-- A status-line button (history icon, no text) that opens the same picker. Tern gives a status
-- formatter 4 ms and turns the hook off until the next reload when it runs longer, so the formatter
-- returns one prebuilt table: no allocation, no garbage-collector step inside the budget.
-- omp/reload-hook.ts turns the hook on again when a new omp chat starts.
local STATUS_SEGMENTS = { { text = "", icon = "history", command = "plugin.omp-groups.reopen" } }
tern.chrome.status(function(_pane)
	return STATUS_SEGMENTS
end)
