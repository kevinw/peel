#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");
const absoluteDistDir = path.join(repoRoot, "dist");
const peelDir = "~/src/peel";

const staticTasks = [
  {
    label: "build ir_pipe",
    command: "cd ~/src/peel/modules/Jai-Shader-Transpiler && jai build_ir_pipe.jai",
  },
  {
    label: "build ALL",
    command: "cd ~/src/peel && jai build.jai",
  },
  {
    label: "compute_semantics_runner",
    command: "~/src/peel/modules/Jai-Shader-Transpiler/headless_ir/test_ir_compute_semantics.sh",
  },
  {
    label: "Run all transpiler tests and build peel apps",
    command: "cd ~/src/peel && jai modules/Jai-Shader-Transpiler/build.jai - -run_tests && jai build.jai",
  },
  {
    label: "runtime tracy",
    command: "cd ~/src/peel && ./tools/runtime-tracy &",
  },
  {
    label: "regenerate peel tasks",
    command: "cd ~/src/peel/tools && node generate_zed_tasks.mjs",
  },
];

const appsDir = path.join(repoRoot, "src", "apps");
const tasksPath = path.join(repoRoot, ".zed", "tasks.json");
const debugEntriesPath = path.join(repoRoot, ".zed", "debug.json");

async function main() {
  const dirEntries = await fs.readdir(appsDir, { withFileTypes: true });
  const appNames = dirEntries
    .filter((d) => d.isFile() && d.name.endsWith(".jai"))
    .map((d) => d.name.slice(0, -4))
    .sort((a, b) => a.localeCompare(b));

  {
    const appTasks = appNames.map((appName) => {
      return {
        label: appName,
        command: `jai ${peelDir}/build.jai - src/apps/${appName}.jai -run -dll`,
      };
    });
    const tasks = [...appTasks, ...staticTasks];
    await fs.writeFile(tasksPath, JSON.stringify(tasks, null, 2), "utf8");
    console.log(`Wrote ${tasks.length} tasks to ${tasksPath}`);
  }

  {
    const debugEntries = appNames.map((appName) => {
      return {
        label: `debug ${appName}`,
        build: {
          command: `jai ${peelDir}/build.jai - src/apps/${appName}.jai`,
        },
        request: "launch",
        mode: "debug",
        program: `./dist/${appName}`,
        cwd: `${absoluteDistDir}`,
        adapter: "CodeLLDB",
      };
    });
    await fs.writeFile(debugEntriesPath, JSON.stringify(debugEntries, null, 2), "utf8");
    console.log(`Wrote ${debugEntries.length} debug entries to ${debugEntriesPath}`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
