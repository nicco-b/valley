#!/bin/sh
# framework_dist.sh — assemble the framework file set (framework.json,
# PLAN_FRAMEWORK FW1) into a dist tree Strata can bundle or read.
#
#   scripts/framework_dist.sh [out_dir]
#
# With no out_dir: prints the manifest census + the computed rev and
# exits (the audit posture). With one: copies every manifest file into
# out_dir preserving paths, plus framework.json and project.godot (the
# scaffold reads its framework sections), and writes framework.rev.json
# {rev, files:{path:sha256}} — provenance the scaffold stamps into each
# game. The rev is COMPUTED (sha256 over sorted "path sha" lines, 12
# hex), never a counter; a live checkout and a dist tree answer the
# same rev for the same bytes. Exits nonzero if a manifest file is
# missing on disk (the manifest may not lie).
set -eu
cd "$(dirname "$0")/.." || exit 1

exec /usr/bin/python3 - "${1:-}" <<'PY'
import hashlib, json, os, shutil, sys

out = sys.argv[1] if len(sys.argv) > 1 and sys.argv[1] else None
manifest = json.load(open("framework.json"))
files = sorted(f for group in manifest["systems"].values() for f in group)
if len(files) != len(set(files)):
    dupes = sorted(set(f for f in files if files.count(f) > 1))
    sys.exit("framework.json lists a file twice: %s" % ", ".join(dupes))

missing = [f for f in files if not os.path.isfile(f)]
if missing:
    sys.exit("framework.json names files not on disk:\n  " + "\n  ".join(missing))

shas = {}
for f in files:
    h = hashlib.sha256()
    with open(f, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    shas[f] = h.hexdigest()

rev = hashlib.sha256(
    "\n".join("%s %s" % (f, shas[f]) for f in files).encode()
).hexdigest()[:12]

counts = {name: len(group) for name, group in manifest["systems"].items()}
print("framework %s rev %s — %d files" % (manifest["framework"], rev, len(files)))
for name in sorted(counts):
    print("  %-22s %d" % (name, counts[name]))

if out:
    os.makedirs(out, exist_ok=True)
    for f in files:
        dest = os.path.join(out, f)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        shutil.copy2(f, dest)
    shutil.copy2("framework.json", os.path.join(out, "framework.json"))
    shutil.copy2("project.godot", os.path.join(out, "project.godot"))
    with open(os.path.join(out, "framework.rev.json"), "w") as fh:
        json.dump({"framework": manifest["framework"], "rev": rev,
                   "files": shas}, fh, indent="\t", sort_keys=True)
        fh.write("\n")
    print("dist -> %s (framework.rev.json rev %s)" % (out, rev))
PY
