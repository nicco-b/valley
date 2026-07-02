#!/bin/sh
# Run the game.
cd "$(dirname "$0")/.." && exec godot --path .
