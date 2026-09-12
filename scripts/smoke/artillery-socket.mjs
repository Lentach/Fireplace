#!/usr/bin/env node
// Runner for artillery-socket.yml: mints one JWT, then runs artillery with it in the env.
//
//   node artillery-socket.mjs [target]            target defaults to http://localhost:3000
//   FP_SMOKE_USER / FP_SMOKE_PASS                  login with these (required against prod)
//   unset                                          register a throwaway smoke_<rand> user on
//                                                  the target (local docker backend only)
//
// Why not an artillery processor: see the header of artillery-socket.yml.
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const here = path.dirname(fileURLToPath(import.meta.url));
const target = (process.argv[2] ?? "http://localhost:3000").replace(/\/$/, "");
const isProd = /fireplace\.ignorelist\.com/.test(target);

let identifier = process.env.FP_SMOKE_USER;
let password = process.env.FP_SMOKE_PASS;

const post = async (p, body) => {
  const res = await fetch(`${target}${p}`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) throw new Error(`${p} ${res.status}: ${await res.text()}`);
  return res.json();
};

if (!identifier) {
  if (isProd) {
    console.error("prod target needs FP_SMOKE_USER/FP_SMOKE_PASS (no throwaway registration on prod)");
    process.exit(2);
  }
  identifier = `smoke_${Math.random().toString(36).slice(2, 10)}`;
  password = "SmokeArtillery-2026!";
  await post("/auth/register", { username: identifier, password });
  console.log(`registered throwaway user ${identifier}`);
}

const { access_token } = await post("/auth/login", { identifier, password });
if (!access_token) {
  console.error("login answered without access_token");
  process.exit(2);
}
console.log(`token minted for ${identifier}; running artillery against ${target}`);

const run = spawnSync("npx", ["artillery", "run", "--target", target, "artillery-socket.yml"], {
  cwd: here,
  stdio: "inherit",
  shell: process.platform === "win32",
  env: { ...process.env, FP_SMOKE_TOKEN: access_token },
});
process.exit(run.status ?? 1);
