#!/bin/sh
# Run the game straight into the Toolkit (the in-game editor): skips the
# title, drops the fly camera over the live world. Dev-only (debug build).
# DECISIONS 2026-07-05, build-out item 1 — the --toolkit boot posture.
cd "$(dirname "$0")/.." && exec godot --path . -- --toolkit
