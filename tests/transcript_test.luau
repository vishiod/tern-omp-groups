-- Run: luau tests/transcript_test.luau
local transcript = require("../transcript")

local failed = 0
local function eq(name: string, got: any, want: any)
	if got ~= want then
		failed += 1
		print(`FAIL {name}: got {tostring(got)}, want {tostring(want)}`)
	end
end

-- agents: a fake folder tree; missing folders raise like tern.fs.list
local tree = {
	["/c"] = { "21.bash.log", "DP6174.md", "DP6174.jsonl", "DP6174", "Notes.jsonl" },
	["/c/DP6174"] = { "DP6174.Reviewer.jsonl", "DP6174.Educator.jsonl", "DP6174.Educator.md" },
}
local function list(path: string): { string }
	local names = tree[path]
	if names == nil then
		error(`no folder {path}`)
	end
	return names
end
local agents = transcript.agents("/c", list)
eq("agents count", #agents, 4)
eq("agent 1 is the lead", agents[1].name, "DP6174")
eq("lead depth", agents[1].depth, 0)
eq("lead file", agents[1].file, "/c/DP6174.jsonl")
eq("children follow their lead, sorted", agents[2].name, "DP6174.Educator")
eq("child depth", agents[2].depth, 1)
eq("child file", agents[2].file, "/c/DP6174/DP6174.Educator.jsonl")
eq("second child", agents[3].name, "DP6174.Reviewer")
eq("sibling after the lead's children", agents[4].name, "Notes")
eq("missing folder has no agents", #transcript.agents("/none", list), 0)

-- wanted
eq("wanted user", transcript.wanted('{"type":"message","id":"a","message":{"role":"user","content":[]}}'), true)
eq("wanted assistant", transcript.wanted('{"type":"message","id":"a","message":{"role":"assistant"}}'), true)
eq("tool result skipped", transcript.wanted('{"type":"message","id":"a","message":{"role":"toolResult"}}'), false)
eq("developer skipped", transcript.wanted('{"type":"message","id":"a","message":{"role":"developer"}}'), false)
eq("custom entry skipped", transcript.wanted('{"type":"custom","data":{"role":"user"}}'), false)

-- markdown
local function msg(role: string, content: any, ts: string?): any
	return { type = "message", timestamp = ts, message = { role = role, content = content } }
end
local entries = {
	{ type = "session", id = "s" },
	msg("user", "Explain the PR stack", "2026-10-16T07:32:44.194Z"),
	msg("assistant", {
		{ type = "thinking", thinking = "secret plan" },
		{ type = "toolCall", name = "read", intent = "Reading the PR", arguments = {} },
	}, "2026-10-16T07:33:00.000Z"),
	msg("toolResult", { { type = "text", text = "file body" } }),
	msg("assistant", { { type = "toolCall", name = "bash", arguments = { i = "Listing files" } } }),
	msg("assistant", { { type = "text", text = "Done." }, { type = "toolCall", name = "write" } }),
	msg("user", { { type = "text", text = "Thanks" }, { type = "image", data = "blob:x" } }),
	msg("developer", { { type = "text", text = "reminder" } }),
}
local md, count = transcript.markdown(entries, 100000)
eq("messages shown, tool-only ones included", count, 5)
eq(
	"markdown",
	md,
	table.concat({
		"## User · 2026-10-16 07:32 UTC\n\nExplain the PR stack",
		"## Assistant · 2026-10-16 07:33 UTC\n\n- `read` Reading the PR\n- `bash` Listing files",
		"## Assistant\n\nDone.\n\n- `write`",
		"## User\n\nThanks\n\n_[image]_",
	}, "\n\n")
)
eq("no thinking", string.find(md, "secret plan", 1, true), nil)
eq("no tool results", string.find(md, "file body", 1, true), nil)

local empty, none = transcript.markdown({ { type = "session" } }, 100)
eq("empty text", empty, "_No messages yet._")
eq("empty count", none, 0)

-- markdown: over the limit, the oldest sections go and the newest stays
local long = {}
for i = 1, 5 do
	table.insert(long, msg("user", `message {i} ` .. string.rep("x", 40)))
end
local cut, total = transcript.markdown(long, 130)
eq("cut count is the messages shown", total, 2)
eq("cut keeps the newest", string.find(cut, "message 5", 1, true) ~= nil, true)
eq("cut drops the oldest", string.find(cut, "message 1", 1, true), nil)
eq("cut says how many", string.sub(cut, 1, 34), "_3 older messages left out._\n\n## U")
local one = transcript.markdown({ msg("user", string.rep("y", 500)) }, 10)
eq("one long section still shows", string.find(one, "yyyy", 1, true) ~= nil, true)

if failed > 0 then
	print(`{failed} test(s) failed`)
	error("tests failed")
end
print("all tests passed")
