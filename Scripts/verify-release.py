#!/usr/bin/env python3
"""Check the actual download archive on a Mac without its build resources."""

import argparse
import json
from pathlib import Path
import stat
import subprocess
import tempfile


def verify(archive: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="herdr-island-release-check-") as directory:
        staging = Path(directory)
        subprocess.run(["ditto", "-x", "-k", str(archive), str(staging)], check=True)
        app = staging / "HerdrIsland.app"
        resources = app / "Contents/Resources"
        if not resources.is_dir():
            raise SystemExit("Archive does not contain HerdrIsland.app resources")
        readonly = [
            str(path.relative_to(app))
            for path in resources.rglob("*")
            if path.is_file() and not path.stat().st_mode & stat.S_IWUSR
        ]
        if readonly:
            raise SystemExit("Resources prevent quarantine removal:\n" + "\n".join(readonly))

        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        # Reproduce browser extraction followed by the documented installation
        # command. Clear the marker before ever launching this fresh app copy.
        subprocess.run([
            "xattr", "-wr", "com.apple.quarantine",
            "0081;00000000;HerdrIslandReleaseCheck;", str(app),
        ], check=True)
        subprocess.run(["xattr", "-dr", "com.apple.quarantine", str(app)], check=True)
        attributes = subprocess.check_output(["xattr", "-r", str(app)], text=True)
        if "com.apple.quarantine" in attributes:
            raise SystemExit("Quarantine attributes remain after the installation command")
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)

        render = staging / "render"
        log = staging / "launch.log"
        with log.open("w") as output:
            try:
                result = subprocess.run([
                    str(app / "Contents/MacOS/HerdrIsland"), "--render", str(render),
                ], cwd=staging, stdout=output, stderr=subprocess.STDOUT, timeout=300)
            except subprocess.TimeoutExpired:
                print(log.read_text()[-8000:])
                raise SystemExit("Packaged application did not finish its render check in 300 seconds")
        if result.returncode != 0:
            print(log.read_text()[-8000:])
            raise SystemExit(f"Packaged application exited with status {result.returncode}")
        manifest = json.loads((render / "manifest.json").read_text())
        if not manifest["scenes"] or not (render / "setupMissing.png").stat().st_size:
            raise SystemExit("Packaged application did not render the expected scenes")
        print("PASS: archive permissions, quarantine removal, signature, and packaged launch")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    verify(args.archive.resolve(strict=True))
