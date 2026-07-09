extends Node
## ToolkitHistory (autoload) — the in-game editor's ONE undo stream (undo
## v2, audit R3). A real bounded command stack: every committed hand action
## pushes an inverse pair, and ⌘Z (in-game Z, the `undo` link verb, and
## Strata's ⌘Z when the pane is front) walks the SAME stack. The old
## cross-tool footgun — Z in biome mode falling through to a placement
## delete — cannot exist here by construction: undo pops the last ACTION,
## never the current mode's guess.
##
## An action is a plain {label, undo, redo} dictionary; the Callables are
## built by the Toolkit (they close over the layer region mementos, the
## record ops, the carved-river record), so the history stays a pure stack
## and the domain knowledge stays home. Actions save-on-commit — the record
## ops write through, the pens mark their layer dirty for the stroke-quiet
## flush — so undo state and disk state cannot diverge within a session.
##
## The stack is session-only: the mementos reference the CURRENT world's
## layers, so a world swap (reload_world, import) clears it; disk is the
## truth across restarts. Bounded so a long authoring session's mementos
## stay memory-flat — the pens store tile RECTS, not whole tiles, and the
## oldest action drops off the bottom when the cap is reached.

## The stack depth. Each pen action holds two small region sub-images; a
## record/river action holds a dict or two — 64 deep is generous and flat.
const CAP := 64

var _undo: Array[Dictionary] = []  # oldest first, newest last
var _redo: Array[Dictionary] = []


## Record a committed action. A fresh edit forks the timeline — the redo
## stack clears — and the oldest action drops when the cap is reached.
func push(action: Dictionary) -> void:
	_undo.append(action)
	if _undo.size() > CAP:
		_undo.pop_front()
	_redo.clear()


func can_undo() -> bool:
	return not _undo.is_empty()


func can_redo() -> bool:
	return not _redo.is_empty()


## Revert the newest action and move it to the redo stack; false (nothing
## touched) when the stack is empty — the caller notices honestly.
func undo() -> bool:
	if _undo.is_empty():
		return false
	var a: Dictionary = _undo.pop_back()
	(a["undo"] as Callable).call()
	_redo.append(a)
	return true


## Re-apply the last undone action; false when there is nothing to redo.
func redo() -> bool:
	if _redo.is_empty():
		return false
	var a: Dictionary = _redo.pop_back()
	(a["redo"] as Callable).call()
	_undo.append(a)
	return true


## The tool label the next undo would touch ("" when empty) — the link's
## `undo` reply names it, as the old per-tool dispatch did.
func peek_undo_label() -> String:
	return String(_undo[-1]["label"]) if not _undo.is_empty() else ""


## The tool label the next redo would touch ("" when empty).
func peek_redo_label() -> String:
	return String(_redo[-1]["label"]) if not _redo.is_empty() else ""


## Drop the whole timeline — a world swap invalidates every memento (they
## point at the layers of the world that just went away).
func clear() -> void:
	_undo.clear()
	_redo.clear()


## Current undo depth (the bounded-stack test reads this).
func depth() -> int:
	return _undo.size()
