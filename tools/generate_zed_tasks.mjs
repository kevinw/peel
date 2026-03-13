#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

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
    label: "regenerate peel tasks",
    command: "cd ~/src/peel/tools && node generate_zed_tasks.mjs",
  },
];

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const repoRoot = path.resolve(__dirname, "..");
const appsDir = path.join(repoRoot, "src", "apps");
const tasksPath = path.join(repoRoot, ".zed", "tasks.json");

function makeAppTask(appName) {
  return {
    label: appName,
    command: `jai ~/src/peel/build.jai - src/apps/${appName}.jai -run -dll`,
  };
}

async function main() {
  const dirEntries = await fs.readdir(appsDir, { withFileTypes: true });
  const appNames = dirEntries
    .filter((d) => d.isFile() && d.name.endsWith(".jai"))
    .map((d) => d.name.slice(0, -4))
    .sort((a, b) => a.localeCompare(b));

  const appTasks = appNames.map(makeAppTask);
  const tasks = [...appTasks, ...staticTasks];
  const out = `${JSON.stringify(tasks, null, 2)}\n`;

  await fs.writeFile(tasksPath, out, "utf8");
  console.log(`Wrote ${tasks.length} tasks to ${tasksPath}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
