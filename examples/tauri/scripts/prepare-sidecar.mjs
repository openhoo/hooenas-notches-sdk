import { execFileSync } from "node:child_process";
import { copyFileSync, chmodSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

if (process.platform !== "darwin")
  throw new Error("The native Hooenas Notches host currently supports macOS 14+ only.");
const example = fileURLToPath(new URL("..", import.meta.url));
const root = path.resolve(example, "../..");
const rustInfo = execFileSync("rustc", ["-vV"], { encoding: "utf8" });
const target =
  process.env.TAURI_ENV_TARGET_TRIPLE ??
  process.env.CARGO_BUILD_TARGET ??
  rustInfo.match(/^host: (.+)$/m)?.[1];
const architectures =
  target === "universal-apple-darwin"
    ? ["arm64", "x86_64"]
    : target === "aarch64-apple-darwin"
      ? ["arm64"]
      : target === "x86_64-apple-darwin"
        ? ["x86_64"]
        : undefined;
if (!architectures) throw new Error(`Unsupported macOS Rust target: ${target}`);
const sidecarDirectory = path.join(example, "src-tauri", "binaries");
mkdirSync(sidecarDirectory, { recursive: true });
const binaries = [];
for (const arch of architectures) {
  const swiftArgs = ["build", "-c", "release", "--arch", arch];
  execFileSync("swift", [...swiftArgs, "--product", "hooenas-notches-host"], {
    cwd: root,
    stdio: "inherit",
  });
  const binDirectory = execFileSync("swift", [...swiftArgs, "--show-bin-path"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  const rustTarget = arch === "arm64" ? "aarch64-apple-darwin" : "x86_64-apple-darwin";
  const thinDestination = path.join(sidecarDirectory, `hooenas-notches-host-${rustTarget}`);
  copyFileSync(path.join(binDirectory, "hooenas-notches-host"), thinDestination);
  chmodSync(thinDestination, 0o755);
  binaries.push(thinDestination);
}
const destination = path.join(sidecarDirectory, `hooenas-notches-host-${target}`);
if (binaries.length > 1)
  execFileSync("/usr/bin/lipo", ["-create", ...binaries, "-output", destination], {
    stdio: "inherit",
  });
chmodSync(destination, 0o755);
console.log(`Prepared native notch sidecar: ${destination}`);
