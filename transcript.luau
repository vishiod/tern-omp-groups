--!strict
-- Pure helpers for omp subagents and chat history. No Tern API here, so plain `luau` can test it.

local transcript = {}

export type Agent = { name: string, file: string, depth: number }

local MAX_DEPTH = 8

-- The subagents saved under a chat's folder, each parent before its children, names sorted.
-- omp saves agent `X` as `<dir>/X.jsonl` and the agents that `X` started under `<dir>/X/`.
-- `list` returns a folder's entry names; it can raise for a missing folder.
function transcript.agents(dir: string, list: (string) -> { string }): { Agent }
	local found: { Agent } = {}
	local function walk(path: string, depth: number)
		local ok, names = pcall(list, path)
		if not ok or depth > MAX_DEPTH then
			return
		end
		local sorted: { string } = {}
		for _, entry in names do
			table.insert(sorted, entry)
		end
		table.sort(sorted)
		local present: { [string]: boolean } = {}
		for _, entry in sorted do
			present[entry] = true
		end
		for _, entry in sorted do
			local name = string.match(entry, "^(.+)%.jsonl$")
			if name then
				table.insert(found, { name = name, file = `{path}/{entry}`, depth = depth })
				if present[name] then
					walk(`{path}/{name}`, depth + 1)
				end
			end
		end
	end
	walk(dir, 0)
	return found
end

-- Whether a session file line holds a user or assistant message. Reads only the start of the
-- line, so the caller does not decode tool results, which are the longest lines.
function transcript.wanted(line: string): boolean
	local head = string.sub(line, 1, 400)
	if string.find(head, '"type":"message"', 1, true) == nil then
		return false
	end
	return string.find(head, '"role":"user"', 1, true) ~= nil
		or string.find(head, '"role":"assistant"', 1, true) ~= nil
end

local function stamp(ts: any): string
	if type(ts) ~= "string" then
		return ""
	end
	local date, time = string.match(ts, "^(%d+%-%d+%-%d+)T(%d+:%d+)")
	return if date then ` · {date} {time} UTC` else ""
end

local function tool_line(part: any): string
	local name = if type(part.name) == "string" then part.name else "tool"
	local intent = part.intent
	if type(intent) ~= "string" and type(part.arguments) == "table" then
		intent = part.arguments.i
	end
	return if type(intent) == "string" and intent ~= "" then `- \`{name}\` {intent}` else `- \`{name}\``
end

-- The text parts and tool-call lines of one message. Thinking parts do not show.
local function parts_of(content: any): (string, string)
	local texts: { string } = {}
	local tools: { string } = {}
	if type(content) == "string" then
		table.insert(texts, content)
	elseif type(content) == "table" then
		for _, part in content do
			if type(part) ~= "table" then
				continue
			end
			if part.type == "text" and type(part.text) == "string" and part.text ~= "" then
				table.insert(texts, part.text)
			elseif part.type == "image" then
				table.insert(texts, "_[image]_")
			elseif part.type == "toolCall" then
				table.insert(tools, tool_line(part))
			end
		end
	end
	return table.concat(texts, "\n\n"), table.concat(tools, "\n")
end

-- Markdown for decoded session file lines: one section per user or assistant message, oldest
-- first. An assistant message with only tool calls joins the section before it. When the text is
-- longer than `max_bytes`, the oldest sections are left out. Returns the text and the number of
-- messages it shows.
function transcript.markdown(entries: { any }, max_bytes: number): (string, number)
	local sections: { string } = {}
	local counts: { number } = {} -- messages in each section
	local last_role: string? = nil
	local ends_with_tools = false
	for _, entry in entries do
		local message = if type(entry) == "table" and entry.type == "message" then entry.message else nil
		local role = if type(message) == "table" then message.role else nil
		if role ~= "user" and role ~= "assistant" then
			continue
		end
		local body, tools = parts_of((message :: any).content)
		if body == "" and tools == "" then
			continue
		end
		if role == "assistant" and body == "" and last_role == "assistant" then
			sections[#sections] ..= (if ends_with_tools then "\n" else "\n\n") .. tools
			counts[#counts] += 1
		else
			local lines = { `## {if role == "user" then "User" else "Assistant"}{stamp(entry.timestamp)}` }
			if body ~= "" then
				table.insert(lines, body)
			end
			if tools ~= "" then
				table.insert(lines, tools)
			end
			table.insert(sections, table.concat(lines, "\n\n"))
			table.insert(counts, 1)
		end
		last_role = role
		ends_with_tools = tools ~= ""
	end
	if #sections == 0 then
		return "_No messages yet._", 0
	end
	local first, size, shown = #sections, 0, 0
	for i = #sections, 1, -1 do
		size += #sections[i] + 2
		if size > max_bytes and i < #sections then
			break
		end
		first = i
		shown += counts[i]
	end
	local out = table.move(sections, first, #sections, 1, {})
	if first > 1 then
		local hidden = 0
		for i = 1, first - 1 do
			hidden += counts[i]
		end
		table.insert(out, 1, `_{hidden} older messages left out._`)
	end
	return table.concat(out, "\n\n"), shown
end

return transcript
