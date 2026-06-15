class_name GameState
extends RefCounted

## Read/write the mutable play state — piece positions only, for now. Kept in a
## SEPARATE file from the scenario package (ADR-0004: "the board and the game
## never mix in one file"); a save references the scenario it belongs to by name
## + config hash so a mismatched board can be flagged on load.

const SAVE_VERSION := "0.1"
const KIND := "krieg-gamestate"

## Serialize current play state to a dict (callers write it where they like).
static func to_dict(scenario: Scenario, pieces: Array) -> Dictionary:
	return {
		"kind": KIND,
		"save_version": SAVE_VERSION,
		"saved_utc": Time.get_datetime_string_from_system(true),
		"scenario": {
			"name": scenario.name(),
			"config_hash": scenario.config_hash(),
			"format_version": scenario.format_version,
		},
		"pieces": pieces,
	}

static func save(path: String, scenario: Scenario, pieces: Array) -> Error:
	var data := to_dict(scenario, pieces)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write save: %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	return OK

## Returns the parsed save dict, or empty on failure.
static func read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Save not found: %s" % path)
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY or data.get("kind", "") != KIND:
		push_error("Not a Krieg save file: %s" % path)
		return {}
	return data

## Does this save belong to the loaded scenario? (name + hash). Caller decides
## whether a mismatch is fatal; the sandbox just warns.
static func matches_scenario(save_data: Dictionary, scenario: Scenario) -> bool:
	var s: Dictionary = save_data.get("scenario", {})
	return s.get("name", "") == scenario.name() \
		and s.get("config_hash", "") == scenario.config_hash()
