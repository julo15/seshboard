import * as vscode from "vscode";
import * as fs from "fs/promises";
import * as os from "os";
import * as path from "path";
import { exec } from "child_process";
import { promisify } from "util";

const log = vscode.window.createOutputChannel("Seshctl");
const execAsync = promisify(exec);

export function activate(context: vscode.ExtensionContext) {
  log.appendLine("Seshctl extension activated");

  context.subscriptions.push(
    vscode.window.registerUriHandler({
      async handleUri(uri: vscode.Uri) {
        log.appendLine(`URI received: path=${uri.path} query=${uri.query}`);
        const params = new URLSearchParams(uri.query);

        if (uri.path === "/focus-terminal") {
          const pidStr = params.get("pid");
          if (!pidStr) {
            log.appendLine("No pid parameter in URI");
            return;
          }
          const targetPid = parseInt(pidStr, 10);
          if (isNaN(targetPid)) {
            log.appendLine(`Invalid pid: ${pidStr}`);
            return;
          }

          log.appendLine(`Looking for terminal with PID ${targetPid}`);
          log.appendLine(
            `Available terminals: ${vscode.window.terminals.length}`
          );

          // Direct PID match
          for (const terminal of vscode.window.terminals) {
            const pid = await terminal.processId;
            log.appendLine(
              `  Terminal "${terminal.name}" pid=${pid}`
            );
            if (pid === targetPid) {
              log.appendLine(`  -> Direct match! Focusing.`);
              terminal.show();
              return;
            }
          }

          // Ancestor match: walk up from targetPid to find a terminal shell
          for (const terminal of vscode.window.terminals) {
            const termPid = await terminal.processId;
            if (termPid && (await isAncestor(termPid, targetPid))) {
              log.appendLine(
                `  -> Ancestor match! Terminal "${terminal.name}" (pid=${termPid}) is ancestor of ${targetPid}. Focusing.`
              );
              terminal.show();
              return;
            }
          }

          log.appendLine(
            `No matching terminal found for PID ${targetPid}`
          );
        } else if (uri.path === "/run-in-terminal") {
          const cmd = params.get("cmd");
          const cwd = params.get("cwd");
          if (!cmd) {
            log.appendLine("No cmd parameter in URI");
            return;
          }

          const decodedCmd = cmd;
          const decodedCwd = cwd ?? undefined;

          log.appendLine(
            `Running in terminal: cmd=${decodedCmd} cwd=${decodedCwd ?? "(default)"}`
          );

          const terminal = vscode.window.createTerminal({
            name: "Resume",
            cwd: decodedCwd,
          });
          terminal.sendText(decodedCmd);
          terminal.show();
        }
      },
    })
  );

  // Terminal -> host window mapping. Writes <pid>.json per terminal so the
  // seshctl CLI can look up which VS Code window hosts a given shell PID.
  void initializeWindowMap(context);
}

async function isAncestor(
  ancestorPid: number,
  childPid: number
): Promise<boolean> {
  let current = childPid;
  for (let i = 0; i < 10; i++) {
    if (current === ancestorPid) {
      return true;
    }
    if (current <= 1) {
      return false;
    }
    try {
      const { stdout } = await execAsync(`ps -p ${current} -o ppid=`);
      const parent = parseInt(stdout.trim(), 10);
      if (isNaN(parent) || parent === current) {
        return false;
      }
      current = parent;
    } catch {
      return false;
    }
  }
  return false;
}

export function deactivate() {}

// ---------------------------------------------------------------------------
// Host-workspace tracking: write <pid>.json per open terminal so the seshctl
// CLI can discover which VS Code window hosts a given shell PID.
// ---------------------------------------------------------------------------

function mapDirectory(): string {
  const override = process.env.SESHCTL_VSCODE_WINDOWS_DIR;
  if (override && override.length > 0) {
    return override;
  }
  return path.join(os.homedir(), ".local", "share", "seshctl", "vscode-windows");
}

async function ensureMapDirectory(): Promise<void> {
  try {
    await fs.mkdir(mapDirectory(), { recursive: true });
  } catch (err) {
    log.appendLine(`Failed to create map directory: ${err}`);
  }
}

// Uses `ps -o lstart=` which returns a full parseable date string, stable
// across days. Divided to epoch seconds. Used to defeat PID recycling.
async function getProcessStartTime(pid: number): Promise<number | null> {
  try {
    const { stdout } = await execAsync(`ps -o lstart= -p ${pid}`);
    const trimmed = stdout.trim();
    if (!trimmed) {
      return null;
    }
    // lstart is a local-TZ string; Date.parse interprets it as local time and returns
    // UTC epoch ms, matching the Swift side's pbi_start_tvsec (UTC epoch seconds).
    const parsed = Date.parse(trimmed);
    if (isNaN(parsed)) {
      return null;
    }
    return Math.floor(parsed / 1000);
  } catch {
    return null;
  }
}

async function writeEntry(pid: number, folders: string[]): Promise<void> {
  const startTime = await getProcessStartTime(pid);
  if (startTime === null) {
    log.appendLine(`Skipping entry for pid=${pid}: could not resolve startTime`);
    return;
  }
  const entry = {
    shellPid: pid,
    startTime,
    workspaceFolders: folders,
  };
  const dir = mapDirectory();
  const finalPath = path.join(dir, `${pid}.json`);
  const tmpPath = `${finalPath}.tmp`;
  try {
    // Atomic write: write to .tmp then rename, so readers never see a partial file.
    await fs.writeFile(tmpPath, JSON.stringify(entry), "utf8");
    await fs.rename(tmpPath, finalPath);
    log.appendLine(
      `Wrote map entry for pid=${pid} folders=${JSON.stringify(folders)}`
    );
  } catch (err) {
    log.appendLine(`Failed to write map entry for pid=${pid}: ${err}`);
    try {
      await fs.unlink(tmpPath);
    } catch {
      // ignore
    }
  }
}

async function removeEntry(pid: number): Promise<void> {
  const finalPath = path.join(mapDirectory(), `${pid}.json`);
  try {
    await fs.unlink(finalPath);
    log.appendLine(`Removed map entry for pid=${pid}`);
  } catch (err: any) {
    if (err?.code !== "ENOENT") {
      log.appendLine(`Failed to remove map entry for pid=${pid}: ${err}`);
    }
  }
}

async function sweepStaleEntries(): Promise<void> {
  const dir = mapDirectory();
  let names: string[];
  try {
    names = await fs.readdir(dir);
  } catch (err) {
    log.appendLine(`Failed to list map directory: ${err}`);
    return;
  }
  for (const name of names) {
    if (!name.endsWith(".json")) {
      continue;
    }
    const filePath = path.join(dir, name);
    try {
      const contents = await fs.readFile(filePath, "utf8");
      const parsed = JSON.parse(contents) as {
        shellPid?: number;
        startTime?: number;
      };
      const pid = parsed.shellPid;
      const recordedStart = parsed.startTime;
      if (typeof pid !== "number" || typeof recordedStart !== "number") {
        await fs.unlink(filePath);
        continue;
      }
      const liveStart = await getProcessStartTime(pid);
      if (liveStart === null || liveStart !== recordedStart) {
        await fs.unlink(filePath);
        log.appendLine(`Swept stale entry pid=${pid}`);
      }
    } catch (err) {
      log.appendLine(`Failed to inspect ${name}, unlinking: ${err}`);
      try {
        await fs.unlink(filePath);
      } catch {
        // ignore
      }
    }
  }
}

async function recordTerminal(terminal: vscode.Terminal): Promise<void> {
  try {
    const pid = await terminal.processId;
    if (!pid) {
      return;
    }
    const folders =
      vscode.workspace.workspaceFolders?.map((f) => f.uri.fsPath) ?? [];
    await writeEntry(pid, folders);
  } catch (err) {
    log.appendLine(`recordTerminal failed: ${err}`);
  }
}

async function initializeWindowMap(
  context: vscode.ExtensionContext
): Promise<void> {
  await ensureMapDirectory();
  await sweepStaleEntries();

  // Backfill entries for terminals already open (e.g. after Developer: Reload Window).
  for (const terminal of vscode.window.terminals) {
    await recordTerminal(terminal);
  }

  context.subscriptions.push(
    vscode.window.onDidOpenTerminal((terminal) => {
      void recordTerminal(terminal);
    })
  );

  context.subscriptions.push(
    vscode.window.onDidCloseTerminal(async (terminal) => {
      try {
        const pid = await terminal.processId;
        if (pid) {
          await removeEntry(pid);
        }
      } catch (err) {
        log.appendLine(`onDidCloseTerminal failed: ${err}`);
      }
    })
  );
}
