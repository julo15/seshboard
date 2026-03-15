"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.activate = activate;
exports.deactivate = deactivate;
const vscode = require("vscode");
function activate(context) {
    context.subscriptions.push(vscode.window.registerUriHandler({
        async handleUri(uri) {
            if (uri.path !== "/focus-terminal") {
                return;
            }
            const params = new URLSearchParams(uri.query);
            const pidStr = params.get("pid");
            if (!pidStr) {
                return;
            }
            const targetPid = parseInt(pidStr, 10);
            if (isNaN(targetPid)) {
                return;
            }
            for (const terminal of vscode.window.terminals) {
                const pid = await terminal.processId;
                if (pid === targetPid) {
                    terminal.show();
                    return;
                }
            }
            // PID might be a child of the terminal's shell — walk up from target
            // to find a terminal whose PID is an ancestor.
            for (const terminal of vscode.window.terminals) {
                const termPid = await terminal.processId;
                if (termPid && (await isAncestor(termPid, targetPid))) {
                    terminal.show();
                    return;
                }
            }
        },
    }));
}
async function isAncestor(ancestorPid, childPid) {
    // Walk up the process tree from childPid looking for ancestorPid.
    // Use `ps` to get parent PIDs.
    const { exec } = require("child_process");
    const { promisify } = require("util");
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
        }
        catch {
            return false;
        }
    }
    return false;
}
function deactivate() { }
//# sourceMappingURL=extension.js.map