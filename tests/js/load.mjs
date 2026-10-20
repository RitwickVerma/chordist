// SPDX-FileCopyrightText: 2026 Ritwick Verma <verma1997@gmail.com>
//
// SPDX-License-Identifier: MIT

// The widget's JS files are QML ".pragma library" scripts. This loads one into
// a plain context (dropping the pragma, which is not JavaScript) and hands back
// its top-level functions, so the logic is tested exactly as the widget runs it.
import { readFileSync } from "node:fs";
import vm from "node:vm";

const JS_DIR = new URL("../../applet/contents/js/", import.meta.url);

export function load(name) {
    const source = readFileSync(new URL(name, JS_DIR), "utf8").replace(/^\.pragma library\s*$/m, "");
    const context = vm.createContext({});
    vm.runInContext(source, context, { filename: name });
    // Values built inside the vm carry that realm's Array/Object prototypes,
    // which strict deep-equality rejects; round-trip them through JSON so a
    // test compares data, not realms.
    const api = {};
    for (const key of Object.keys(context)) {
        const value = context[key];
        api[key] = typeof value === "function"
            ? (...args) => {
                const result = value(...args);
                return result === undefined ? undefined : JSON.parse(JSON.stringify(result));
            }
            : value;
    }
    return api;
}
