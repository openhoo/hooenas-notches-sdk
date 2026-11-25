#!/usr/bin/env python3
"""Build the universal SDK development helper and its release checksum on macOS."""

import gzip
import hashlib
import json
import shutil
import subprocess
import tarfile
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HOST = "hooenas-notches-host"


def capture(*args):
    return subprocess.check_output(args, cwd=ROOT, text=True).strip()


def package():
    version = json.loads((ROOT / "packages/client/package.json").read_text())["version"]
    name = f"{HOST}-v{version}-universal-macos"
    output = ROOT / "output" / "release" / f"v{version}"
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output) as tmp:
        staging = Path(tmp) / name
        staging.mkdir()
        slices = []
        for arch in ("arm64", "x86_64"):
            swift = ("swift", "build", "-c", "release", "--arch", arch, "-Xswiftc", "-warnings-as-errors")
            subprocess.run([*swift, "--product", HOST], cwd=ROOT, check=True)
            slices.append(Path(capture(*swift, "--show-bin-path")) / HOST)
        binary = staging / HOST
        subprocess.run(["/usr/bin/lipo", "-create", *slices, "-output", binary], check=True)
        # Ad-hoc signing supports local development without a distribution identity.
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none", binary], check=True)
        subprocess.run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", binary], check=True)
        if set(capture("/usr/bin/lipo", "-archs", binary).split()) != {"arm64", "x86_64"}:
            raise ValueError("The helper must contain both macOS architectures.")
        if capture(binary, "--version") != f"{HOST} {version} (protocol 1)":
            raise ValueError("The helper and client versions do not match.")

        for filename in ("LICENSE", "THIRD_PARTY_NOTICES.md", "LICENSES/Cua-Spaces-Notch-LICENSE.txt"):
            destination = staging / filename
            destination.parent.mkdir(exist_ok=True)
            shutil.copyfile(ROOT / filename, destination)
        shutil.copyfile(ROOT / "docs/host-protocol.md", staging / "host-protocol.md")
        (staging / "README.txt").write_text(
            f"Hooenas Notches native host {version} (protocol 1)\n"
            "macOS 14+, universal arm64 + x86_64.\n"
            "This development helper is ad-hoc signed, not distribution-signed or notarized.\n"
            "FSL-1.1-MIT applies; read LICENSE and THIRD_PARTY_NOTICES.md.\n"
            "Use --version or --help. JSON Lines framing and commands are in host-protocol.md.\n"
            "Native SwiftUI and TypeScript/Tauri integration: https://github.com/openhoo/hooenas-notches-sdk\n",
            encoding="utf-8",
        )

        archive = Path(tmp) / f"{name}.tar.gz"
        # Exclude workstation owner, timestamps, resource forks and unrelated output.
        with archive.open("wb") as stream, gzip.GzipFile(filename="", mode="wb", fileobj=stream, mtime=0) as zipped:
            with tarfile.open(mode="w", fileobj=zipped, format=tarfile.USTAR_FORMAT) as tar:
                for path in [staging, *sorted(staging.rglob("*"))]:
                    info = tar.gettarinfo(str(path), str(path.relative_to(staging.parent)))
                    info.uid = info.gid = info.mtime = 0
                    info.uname = info.gname = ""
                    info.mode = 0o755 if path.is_dir() or path == binary else 0o644
                    if path.is_dir():
                        tar.addfile(info)
                    else:
                        with path.open("rb") as content:
                            tar.addfile(info, content)
        checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
        sums = Path(tmp) / "SHA256SUMS.txt"
        sums.write_text(f"{checksum}  {archive.name}\n", encoding="utf-8")
        archive.replace(output / archive.name)
        sums.replace(output / sums.name)
    print(f"Prepared {output / archive.name}\nSHA-256: {checksum}")


if __name__ == "__main__":
    package()
