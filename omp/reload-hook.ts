// omp hook: when a new omp chat starts inside Tern, turn the omp-groups plugin on again if Tern
// turned it off. Tern disables a plugin hook that runs past its time budget (4 ms for the status
// button) "until reload", and says so only in its log. A reload of the plugin restores it.
//
// Install: ln -sf "$PWD/omp/reload-hook.ts" ~/.omp/agent/hooks/post/tern-omp-groups.ts
import type { ExtensionAPI } from "@oh-my-pi/pi-coding-agent";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";

const LOG_FILE = path.join(os.homedir(), "Library/Logs/Tern/tern.log");
const STATE_FILE = path.join(os.homedir(), ".local/state/tern-omp-groups/handled-disable");
const LOG_TAIL_BYTES = 1024 * 1024;

const DISABLED = /^(\S+)\s+(\d+)\s.*disabled until reload plugin="omp-groups"/;
const STARTED = /^\S+\s+(\d+)\s.*started app="Tern"/;

/**
 * The timestamp of the latest "disabled until reload" line for omp-groups that still applies, or
 * undefined. A line stops applying when Tern started again after it (a new process loads every
 * plugin fresh) or when this hook already reloaded for it (`handled`).
 */
export function pendingDisable(log: string, handled: string | undefined): string | undefined {
	let currentPid: string | undefined;
	let disabled: { at: string; pid: string } | undefined;
	for (const line of log.split("\n")) {
		const started = STARTED.exec(line);
		if (started) {
			currentPid = started[1];
			continue;
		}
		const off = DISABLED.exec(line);
		if (off) {
			disabled = { at: off[1], pid: off[2] };
		}
	}
	if (disabled === undefined || disabled.at === handled) {
		return undefined;
	}
	if (currentPid !== undefined && disabled.pid !== currentPid) {
		return undefined;
	}
	return disabled.at;
}

function readTail(file: string, bytes: number): string {
	const fd = fs.openSync(file, "r");
	try {
		const size = fs.fstatSync(fd).size;
		const start = Math.max(0, size - bytes);
		const buffer = Buffer.alloc(size - start);
		fs.readSync(fd, buffer, 0, buffer.length, start);
		return buffer.toString("utf8");
	} finally {
		fs.closeSync(fd);
	}
}

function readHandled(): string | undefined {
	try {
		return fs.readFileSync(STATE_FILE, "utf8").trim() || undefined;
	} catch {
		return undefined;
	}
}

export default function (pi: ExtensionAPI): void {
	pi.on("session_start", async () => {
		// TERN_PANE is set in every Tern pane; TERN_WINDOW_KEY can be present but empty.
		if (!process.env.TERN_PANE || !fs.existsSync(LOG_FILE)) {
			return; // not inside Tern
		}
		const at = pendingDisable(readTail(LOG_FILE, LOG_TAIL_BYTES), readHandled());
		if (at === undefined) {
			return;
		}
		// Record first, so chats that start at the same moment do not reload again.
		fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
		fs.writeFileSync(STATE_FILE, `${at}\n`);
		const result = await pi.exec("tern", ["plugin", "reload"]);
		if (result.code === 0) {
			pi.logger.info(`tern-omp-groups: plugin was off since ${at}; reloaded it`);
		} else {
			pi.logger.warn(`tern-omp-groups: tern plugin reload failed: ${result.stderr || result.stdout}`);
		}
	});
}
