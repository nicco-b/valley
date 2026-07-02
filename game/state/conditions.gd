class_name Conditions
## The shared condition language. Dialogue choices, quest steps, and any
## future gate all evaluate the same way. All keys present must pass (AND):
##   {"flag": "npc.wanderer.met"}        — flag is set
##   {"not_flag": "world.x"}             — flag is not set
##   {"gte": ["player.times_sat", 3]}    — numeric value at least n
##   {"item": ["dried_bloom", 2]}        — inventory holds at least n


static func eval(c: Dictionary) -> bool:
	if c.has("flag") and not WorldState.has_flag(c.flag):
		return false
	if c.has("not_flag") and WorldState.has_flag(c.not_flag):
		return false
	if c.has("gte") and int(WorldState.get_value(c.gte[0], 0)) < int(c.gte[1]):
		return false
	if c.has("item") and Items.count(c.item[0]) < int(c.item[1]):
		return false
	return true
