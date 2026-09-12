extends Node

# Deeds of the Kingdom — the achievement brain.
#
# The game only writes (bump/flag). This class is the only reader of the
# persisted cfg and the only evaluator of triggers. UI layers listen to
# deed_unlocked. No scoring; one-player; local-only.
#
# Persistence layout (user://deeds.cfg):
#   [stats]     — int counters and bool flags keyed by stat name
#   [celebrated]— ids = comma-separated string of ever-unlocked deed ids
#
# Manifest (res://achievements/achievements.manifest):
#   JSON array of objects, display order is first-class.
#   Validated at load; malformed entries warn+skip, others continue.

signal deed_unlocked(id: String)

## Injectable paths for tests (default values used in production).
var cfg_path: String = "user://deeds.cfg"
var manifest_path: String = "res://achievements/achievements.manifest"

# Validated manifest entries in file order.
var _entries: Array[Dictionary] = []

# ConfigFile backing [stats] and [celebrated]
var _cfg: ConfigFile = ConfigFile.new()

# Set of ids we have already celebrated (persisted in [celebrated]).
var _celebrated: Dictionary = {}   # id -> true

# Charset for valid ids: ^[a-z0-9_-]{1,32}$
const _ID_REGEX_PATTERN := "^[a-z0-9_-]{1,32}$"
var _id_regex: RegEx = RegEx.new()

# Unknown stats we have already warned about (warn once per stat per load).
var _warned_stats: Dictionary = {}


func _ready() -> void:
	_id_regex.compile(_ID_REGEX_PATTERN)
	reload()


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Increment a counter stat by `by` (default 1), save, re-evaluate.
func bump(stat: String, by: int = 1) -> void:
	var current: int = _cfg.get_value("stats", stat, 0)
	_cfg.set_value("stats", stat, current + by)
	_cfg.save(cfg_path)
	_evaluate()


## Set a boolean flag stat to true, save, re-evaluate.
func flag(name: String) -> void:
	_cfg.set_value("stats", name, true)
	_cfg.save(cfg_path)
	_evaluate()


## Returns true if deed `id` has been unlocked.
func is_unlocked(id: String) -> bool:
	return _celebrated.has(id)


## Returns validated manifest entries in file order.
## Each entry has keys: id, name, text, solid, ghost, trigger, secret.
func entries() -> Array[Dictionary]:
	return _entries


## Re-reads manifest + cfg. Used by tests and future toybox.
func reload() -> void:
	_cfg = ConfigFile.new()
	_cfg.load(cfg_path)   # missing file = fresh state, not an error
	_celebrated = {}
	_warned_stats = {}
	_load_celebrated()
	_load_manifest()


# ---------------------------------------------------------------------------
# Private: cfg helpers
# ---------------------------------------------------------------------------

func _load_celebrated() -> void:
	var raw: String = str(_cfg.get_value("celebrated", "ids", ""))
	if raw == "":
		return
	for id in raw.split(","):
		var trimmed := id.strip_edges()
		if trimmed != "":
			_celebrated[trimmed] = true


func _save_celebrated() -> void:
	var ids := ",".join(_celebrated.keys())
	_cfg.set_value("celebrated", "ids", ids)
	_cfg.save(cfg_path)


# ---------------------------------------------------------------------------
# Private: manifest loading
# ---------------------------------------------------------------------------

func _load_manifest() -> void:
	_entries = []

	if not FileAccess.file_exists(manifest_path):
		push_warning("Deeds: manifest not found at %s — no deeds loaded" % manifest_path)
		return

	var fa := FileAccess.open(manifest_path, FileAccess.READ)
	if fa == null:
		push_warning("Deeds: cannot open manifest at %s" % manifest_path)
		return

	var text := fa.get_as_text()
	fa.close()

	var parsed = JSON.parse_string(text)
	if parsed == null or not (parsed is Array):
		push_warning("Deeds: manifest is not a valid JSON array at %s" % manifest_path)
		return

	var raw_entries: Array = parsed
	var valid_entries: Array[Dictionary] = []
	var seen_ids: Dictionary = {}

	for i in raw_entries.size():
		var raw = raw_entries[i]
		if not (raw is Dictionary):
			push_warning("Deeds: manifest entry %d is not an object — skipped" % i)
			continue
		var entry: Dictionary = raw

		# Validate id
		var id = entry.get("id", "")
		if not (id is String) or id == "":
			push_warning("Deeds: manifest entry %d has missing/invalid id — skipped" % i)
			continue
		if _id_regex.search(id) == null:
			push_warning("Deeds: manifest entry id %s has invalid charset — skipped" % id)
			continue
		if seen_ids.has(id):
			push_warning("Deeds: manifest entry id %s is duplicate — skipped" % id)
			continue

		# Validate required string fields
		var name_val = entry.get("name", "")
		var text_val = entry.get("text", "")
		var solid_val = entry.get("solid", "")
		var trigger_val = entry.get("trigger", "")

		if not (name_val is String) or name_val == "":
			push_warning("Deeds: manifest entry %s has missing name — skipped" % id)
			continue
		if not (text_val is String):
			push_warning("Deeds: manifest entry %s has invalid text — skipped" % id)
			continue
		if not (solid_val is String) or solid_val == "":
			push_warning("Deeds: manifest entry %s has missing solid image — skipped" % id)
			continue
		if not (trigger_val is String) or trigger_val == "":
			push_warning("Deeds: manifest entry %s has missing trigger — skipped" % id)
			continue

		# Validate trigger syntax
		if not _is_valid_trigger_syntax(trigger_val, id):
			continue  # warning already emitted inside

		var ghost_val: String = str(entry.get("ghost", "")) if entry.has("ghost") else ""
		var secret_val: bool = bool(entry.get("secret", false))

		var validated: Dictionary = {
			"id": id,
			"name": str(name_val),
			"text": str(text_val),
			"solid": str(solid_val),
			"ghost": ghost_val,
			"trigger": str(trigger_val),
			"secret": secret_val,
		}

		seen_ids[id] = true
		valid_entries.append(validated)

	# Cycle / self-reference detection for unlocked: triggers
	var disabled_ids := _find_cycle_ids(valid_entries)
	if disabled_ids.size() > 0:
		var names := ",".join(disabled_ids.keys())
		push_warning("Deeds: cycle detected among unlocked: triggers — disabled: %s" % names)
		var filtered: Array[Dictionary] = []
		for e in valid_entries:
			if not disabled_ids.has(e["id"]):
				filtered.append(e)
		valid_entries = filtered

	_entries = valid_entries

	# Warn once for unknown stats referenced in count: triggers
	_warn_unknown_stats()


func _is_valid_trigger_syntax(trigger: String, entry_id: String) -> bool:
	if trigger.begins_with("count:"):
		# count:<stat>>=N
		var rest := trigger.substr(6)  # after "count:"
		var gte_idx := rest.find(">=")
		if gte_idx <= 0:
			push_warning("Deeds: entry %s trigger '%s' malformed (count: requires >=) — skipped" % [entry_id, trigger])
			return false
		var stat_part := rest.substr(0, gte_idx)
		var n_part := rest.substr(gte_idx + 2)
		if stat_part == "" or not n_part.is_valid_int():
			push_warning("Deeds: entry %s trigger '%s' malformed — skipped" % [entry_id, trigger])
			return false
		if int(n_part) < 0:
			# A negative threshold is always-true — silent auto-unlock is an
			# authoring bug, not a feature (review catch).
			push_warning("Deeds: entry %s trigger '%s' has a negative threshold — skipped" % [entry_id, trigger])
			return false
		return true
	elif trigger.begins_with("flag:"):
		var flag_name := trigger.substr(5)
		if flag_name == "":
			push_warning("Deeds: entry %s trigger '%s' has empty flag name — skipped" % [entry_id, trigger])
			return false
		return true
	elif trigger.begins_with("unlocked:"):
		var ids_part := trigger.substr(9)
		if ids_part == "":
			push_warning("Deeds: entry %s trigger '%s' has empty id list — skipped" % [entry_id, trigger])
			return false
		var dep_ids := ids_part.split(",")
		for dep in dep_ids:
			var d := dep.strip_edges()
			if d == "":
				push_warning("Deeds: entry %s trigger '%s' has empty id in list — skipped" % [entry_id, trigger])
				return false
		return true
	else:
		push_warning("Deeds: entry %s trigger '%s' has unknown clause type — skipped" % [entry_id, trigger])
		return false


func _find_cycle_ids(entries: Array[Dictionary]) -> Dictionary:
	# Build a map of id -> set of unlocked: deps
	var dep_map: Dictionary = {}  # id -> Array of dep ids
	var all_ids: Dictionary = {}
	for e in entries:
		all_ids[e["id"]] = true
	for e in entries:
		var trigger: String = e["trigger"]
		if trigger.begins_with("unlocked:"):
			var ids_part := trigger.substr(9)
			var deps: Array = []
			for dep in ids_part.split(","):
				var d := dep.strip_edges()
				if d != "":
					deps.append(d)
			dep_map[e["id"]] = deps
		else:
			dep_map[e["id"]] = []

	# Check for self-references and cycles using DFS
	var disabled: Dictionary = {}

	# First pass: self-references
	for id in dep_map:
		var deps: Array = dep_map[id]
		for dep in deps:
			if dep == id:
				disabled[id] = true

	# Cycle detection: iterative DFS with coloring (0=white, 1=gray, 2=black)
	var color: Dictionary = {}
	for id in dep_map:
		color[id] = 0  # white

	for start in dep_map.keys():
		if color.get(start, 0) == 2:
			continue  # already fully visited
		if color.get(start, 0) == 1:
			continue
		# DFS from start
		var stack: Array = [[start, 0]]  # [id, dep_index]
		var path: Array = []

		while stack.size() > 0:
			var top = stack[stack.size() - 1]
			var cur_id: String = top[0]
			var dep_idx: int = top[1]

			if dep_idx == 0:
				if color.get(cur_id, 0) == 1:
					# Back edge = cycle — mark all in path from cur_id as disabled
					var cycle_start := path.find(cur_id)
					if cycle_start >= 0:
						for k in range(cycle_start, path.size()):
							disabled[path[k]] = true
					stack.pop_back()
					continue
				color[cur_id] = 1  # gray
				path.append(cur_id)

			var deps: Array = dep_map.get(cur_id, [])
			if dep_idx < deps.size():
				var dep: String = deps[dep_idx]
				top[1] += 1
				if dep_map.has(dep):
					if color.get(dep, 0) == 0:
						stack.append([dep, 0])
					elif color.get(dep, 0) == 1:
						# Cycle found
						var cycle_start := path.find(dep)
						if cycle_start >= 0:
							for k in range(cycle_start, path.size()):
								disabled[path[k]] = true
						disabled[cur_id] = true
				else:
					# dep not in manifest — entry references non-existent id
					# not a cycle but invalid dep; don't disable here (just won't trigger)
					pass
			else:
				color[cur_id] = 2  # black
				path.pop_back()
				stack.pop_back()

	return disabled


func _warn_unknown_stats() -> void:
	# Collect all stats referenced by count: triggers in valid entries
	# We can't know at load time which stats "exist" (they're created on first bump)
	# So we just note them; _evaluate will warn once per unknown stat when actually triggered.
	# This function intentionally does nothing at load — warnings happen on first evaluate
	pass


# ---------------------------------------------------------------------------
# Private: trigger evaluation
# ---------------------------------------------------------------------------

func _evaluate() -> void:
	# Loop until stable — cascading unlocked: triggers can unlock in the same write.
	# Collect all newly-unlocked ids in manifest order before emitting signals.
	var all_newly: Array[String] = []

	# Belt-and-braces: cycles are removed at load, so each pass must unlock
	# at least one new id — entries.size()+1 passes is mathematically enough.
	var _passes_left := _entries.size() + 1
	while _passes_left > 0:
		_passes_left -= 1
		var newly: Array[String] = []
		for entry in _entries:
			var id: String = entry["id"]
			if _celebrated.has(id):
				continue  # already celebrated
			if _triggers_met(entry):
				newly.append(id)
		if newly.size() == 0:
			break
		# Update _celebrated immediately so cascading unlocked: triggers see them
		for id in newly:
			_celebrated[id] = true
			all_newly.append(id)

	# Persist once, then emit signals in the order they were collected
	if all_newly.size() > 0:
		_save_celebrated()
	for id in all_newly:
		deed_unlocked.emit(id)


func _triggers_met(entry: Dictionary) -> bool:
	var trigger: String = entry["trigger"]

	if trigger.begins_with("count:"):
		var rest := trigger.substr(6)
		var gte_idx := rest.find(">=")
		var stat_name := rest.substr(0, gte_idx)
		var threshold := int(rest.substr(gte_idx + 2))
		# Warn once if this stat has never been recorded
		if not _cfg.has_section_key("stats", stat_name) and not _warned_stats.has(stat_name):
			_warned_stats[stat_name] = true
			push_warning("Deeds: trigger references unknown stat '%s' — will never fire" % stat_name)
		var current: int = _cfg.get_value("stats", stat_name, 0)
		return current >= threshold

	elif trigger.begins_with("flag:"):
		var flag_name := trigger.substr(5)
		return bool(_cfg.get_value("stats", flag_name, false))

	elif trigger.begins_with("unlocked:"):
		var ids_part := trigger.substr(9)
		for dep in ids_part.split(","):
			var d := dep.strip_edges()
			if d != "" and not _celebrated.has(d):
				return false
		return true

	return false
