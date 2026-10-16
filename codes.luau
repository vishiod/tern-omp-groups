--!strict
-- Pure helpers for omp chat group codes. No Tern API here, so plain `luau` can test it.

local codes = {}

export type Chat = { id: string, title: string, updated: number, group: string?, [string]: any }
export type Group = { code: string, chats: { Chat } }

local WORK_TYPES = {
	PR = true,
	EXPLAIN = true,
	TRIAGE = true,
	PLAN = true,
	BUILD = true,
	OMP = true,
	OPS = true,
	MISC = true,
}

-- The raw code at the start of an omp title (`[glyphs ]CODE: title`), or nil.
-- Leading glyphs (icons, spinners) may not contain ASCII letters or digits.
function codes.parse(title: string): string?
	local prefix, code = string.match(title, "^(.-)(%u[%u%d]*): ")
	if prefix == nil or code == nil then
		return nil
	end
	if prefix ~= "" and (string.find(prefix, "%w") ~= nil or string.sub(prefix, -1) ~= " ") then
		return nil
	end
	if #code < 2 or #code > 16 then
		return nil
	end
	return code
end

-- The group a code belongs to: a work type or Jira code as is, anything else MISC.
function codes.normalize(code: string): string
	if WORK_TYPES[code] then
		return code
	end
	local letters, digits = string.match(code, "^(%u+)(%d+)$")
	if letters and digits and #letters >= 2 and #letters <= 10 and #digits <= 6 then
		return code
	end
	return "MISC"
end

-- The title without its leading glyphs and code.
function codes.strip(title: string): string
	local code = codes.parse(title)
	if code == nil then
		return title
	end
	local _, last = string.find(title, code .. ": ", 1, true)
	return string.sub(title, (last :: number) + 1)
end

-- The group of a title; titles without a code go to MISC.
function codes.group_of(title: string): string
	local code = codes.parse(title)
	return if code then codes.normalize(code) else "MISC"
end

-- Chats grouped: a chat's explicit `group` (its Tern session) wins over its title code.
-- Groups are ordered by their newest chat; chats newest first.
function codes.group_chats(rows: { Chat }): { Group }
	local by_code: { [string]: Group } = {}
	local groups: { Group } = {}
	for _, row in rows do
		local code = row.group or codes.group_of(row.title)
		local group = by_code[code]
		if group == nil then
			group = { code = code, chats = {} }
			by_code[code] = group
			table.insert(groups, group)
		end
		table.insert(group.chats, row)
	end
	for _, group in groups do
		table.sort(group.chats, function(a, b)
			return a.updated > b.updated
		end)
	end
	table.sort(groups, function(a, b)
		local na, nb = a.chats[1].updated, b.chats[1].updated
		if na ~= nb then
			return na > nb
		end
		return a.code < b.code
	end)
	return groups
end

-- Short age text for a number of seconds.
function codes.age(seconds: number): string
	if seconds < 60 then
		return "now"
	elseif seconds < 3600 then
		return `{seconds // 60}m`
	elseif seconds < 86400 then
		return `{seconds // 3600}h`
	end
	return `{seconds // 86400}d`
end

return codes
