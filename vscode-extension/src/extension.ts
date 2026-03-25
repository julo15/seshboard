import * as vscode from "vscode";

const log = vscode.window.createOutputChannel("Seshctl");

export function activate(context: vscode.ExtensionContext) {
  log.appendLine("Seshctl extension activated");

  context.subscriptions.push(
    vscode.window.registerUriHandler({
      async handleUri(uri: vscode.Uri) {
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

          const decodedCmd = decodeURIComponent(cmd);
          const decodedCwd = cwd ? decodeURIComponent(cwd) : undefined;

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
}

async function isAncestor(
  ancestorPid: number,
  childPid: number
): Promise<boolean> {
  const { exec } = require("child_process") as typeof import("child_process");
  const { promisify } = require("util") as typeof import("util");
  const execAsync = promisify(exec);

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
