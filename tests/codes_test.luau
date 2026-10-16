-- Run: luau tests/codes_test.luau
local codes = require("../codes")

local failed = 0
local function eq(name: string, got: any, want: any)
	if got ~= want then
		failed += 1
		print(`FAIL {name}: got {tostring(got)}, want {tostring(want)}`)
	end
end

local ICON = utf8.char(0xF02DA)

-- parse
eq("parse plain", codes.parse("PR: Review api PR 42"), "PR")
eq("parse icon", codes.parse(ICON .. " HIST: Improve chat history"), "HIST")
eq("parse issue key", codes.parse("ABC123: Add rate limit field"), "ABC123")
eq("parse two glyphs", codes.parse("⠋ " .. ICON .. " OMP: Fix setup"), "OMP")
eq("parse shell title", codes.parse("π > Update omp"), nil)
eq("parse no code", codes.parse("Update omp"), nil)
eq("parse empty", codes.parse(""), nil)
eq("parse lowercase", codes.parse("pr: something"), nil)
eq("parse word before code", codes.parse("vim PR: notes"), nil)
eq("parse colon without space", codes.parse("PR:x"), nil)
eq("parse too long", codes.parse("ABCDEFGHIJKLMNOPQ: x"), nil)
eq("parse one letter", codes.parse("A: x"), nil)

-- normalize
eq("normalize work type", codes.normalize("EXPLAIN"), "EXPLAIN")
eq("normalize issue key", codes.normalize("ABC123"), "ABC123")
eq("normalize issue key short project", codes.normalize("XY42"), "XY42")
eq("normalize unknown", codes.normalize("WEIRD"), "MISC")
eq("normalize digits only after one letter", codes.normalize("A123"), "MISC")
eq("normalize too many digits", codes.normalize("ABC1234567"), "MISC")

-- strip
eq("strip icon and code", codes.strip(ICON .. " HIST: Improve chat history"), "Improve chat history")
eq("strip plain", codes.strip("PR: Review api PR 42"), "Review api PR 42")
eq("strip no code", codes.strip("Update omp"), "Update omp")

-- group_chats
local groups = codes.group_chats({
	{ id = "a", title = "PR: old review", updated = 100 },
	{ id = "b", title = "ABC123: newest", updated = 300 },
	{ id = "c", title = "PR: new review", updated = 200 },
	{ id = "d", title = "Update omp", updated = 50 },
	{ id = "e", title = ICON .. " ODD: odd code", updated = 150 },
})
eq("groups count", #groups, 3)
eq("group 1 code", groups[1].code, "ABC123")
eq("group 2 code", groups[2].code, "PR")
eq("group 2 newest first", groups[2].chats[1].id, "c")
eq("group 2 second", groups[2].chats[2].id, "a")
eq("group 3 code", groups[3].code, "MISC")
eq("group 3 newest first", groups[3].chats[1].id, "e")
eq("group 3 untitled code chat", groups[3].chats[2].id, "d")

-- group_chats: an explicit group (the chat's Tern session) wins over the title code
local placed = codes.group_chats({
	{ id = "x", title = "PR: moved by hand", updated = 20, group = "ABC123" },
	{ id = "y", title = "ABC123: in place", updated = 10 },
	{ id = "z", title = ICON .. " RENAME: ABC9: renamed", updated = 5, group = "PR" },
})
eq("explicit groups count", #placed, 2)
eq("explicit group wins", placed[1].code, "ABC123")
eq("explicit group joins title group", #placed[1].chats, 2)
eq("renamed chat keeps its session", placed[2].code, "PR")

-- age
eq("age now", codes.age(30), "now")
eq("age minutes", codes.age(5 * 60), "5m")
eq("age hours", codes.age(3 * 3600 + 10), "3h")
eq("age days", codes.age(2 * 86400), "2d")
eq("age negative", codes.age(-5), "now")

if failed > 0 then
	print(`{failed} test(s) failed`)
	error("tests failed")
end
print("all tests passed")
