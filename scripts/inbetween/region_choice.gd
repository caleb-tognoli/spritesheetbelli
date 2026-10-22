class_name RegionChoice
extends RefCounted
## How the regions of [RegionMotions] choose their motions together from the candidates
## found: min-sum belief propagation over the regions touching, each region's choices
## scored by how well it lands on the other key, and each two touching by how far they
## come apart.

## Motions each region chooses from: its own best few, and its neighbours' best
const OWN_CHOICES := 12
const SHARED_CHOICES := 3
## How much neighbours coming apart costs per pixel of border, each pixel they're apart
## (beyond one, up to [constant GAP_CAP]): little for unlike colours, which are likely
## parts that move on their own, much for alike ones, likely shades of one thing
const APART_COST := 0.03
const ALIKE_APART_COST := 1.0
const ALIKE := 0.15
const GAP_CAP := 6.0
## Points of a border, and of each region, compared when scoring them coming apart
const BORDER_POINTS := 10
const REGION_POINTS := 32
## Rounds of belief propagation
const ROUNDS := 30
## Edges between regions passing messages on each thread at least
const MESSAGES_LEAST := 32

var motions: RegionMotions
var regions: KeyRegions


## Each of [param of_motions]' regions' motion, chosen together from [param candidates]
static func choose(of_motions: RegionMotions, candidates: Array[Transform2D]) -> Array[Transform2D]:
	var choice := RegionChoice.new()
	choice.motions = of_motions
	choice.regions = of_motions.regions
	return choice._choose(candidates)


## The regions of [param of_regions], biggest first
static func biggest_first(of_regions: KeyRegions) -> PackedInt32Array:
	var sizes := PackedInt32Array()
	for pixels in of_regions.pixels:
		sizes.append(pixels.size())
	return largest_first(sizes)


## The places in [param sizes], largest first
static func largest_first(sizes: PackedInt32Array) -> PackedInt32Array:
	var keys := PackedInt64Array()
	for k in sizes.size():
		keys.append(-sizes[k] * 4294967296 + k)
	keys.sort()
	var order := PackedInt32Array()
	for key in keys:
		order.append(key & 0xFFFFFFFF)
	return order


## [param work] called with each index from 0 to the size of [param order] less one and
## the next, by index: called on threads (see [method Parallel.split]), each taking the next
## index of [param order] left as it's done, so work of uneven size is spread evenly
static func shared(order: PackedInt32Array, work: Callable) -> Array:
	var results := []
	results.resize(order.size())
	var next := [0]
	var lock := Mutex.new()
	var take := func(_start: int, _end: int) -> Array:
		var done := []
		while true:
			lock.lock()
			var k: int = next[0]
			next[0] = k + 1
			lock.unlock()
			if k >= order.size():
				return done
			done.append([order[k], work.call(order[k], order[k] + 1)])
		return done
	for part: Array in Parallel.split(order.size(), 1, take):
		for entry: Array in part:
			results[entry[0]] = entry[1]
	return results


## Each region's motion, chosen together from [param candidates]
func _choose(candidates: Array[Transform2D]) -> Array[Transform2D]:
	var count := regions.count()
	var biggest := biggest_first(regions)
	# Each region's own best few, as candidates, and what candidates cost each region,
	# worked out for each region on its own, so they're shared out among threads
	var own: Array[PackedInt32Array] = []
	var landing_costs: Array[PackedFloat64Array] = []
	for part: Array in shared(biggest, _own_best.bind(candidates)):
		own.append_array(part[0])
		landing_costs.append_array(part[1])
	var neighbours: Array[Array] = []
	for r in count:
		neighbours.append(regions.neighbours_of(r))
	# What the neighbours' best cost each region, where not worked out yet
	var missing := _missing_costs.bind(candidates, own, landing_costs, neighbours)
	for part: Array in shared(biggest, missing):
		for entry: Array in part:
			landing_costs[entry[0]][entry[1]] = entry[2]
	# Each region's choices: its own and its neighbours' best, and what each costs. A
	# candidate is a choice once: twice, it would only cost and be chosen alike.
	var choices: Array[Array] = []
	var costs: Array[PackedFloat32Array] = []
	for r in count:
		var picks := own[r].duplicate()
		for k: int in neighbours[r]:
			for c in own[k].slice(0, SHARED_CHOICES):
				if not picks.has(c):
					picks.append(c)
		var list: Array[Transform2D] = []
		var size := regions.pixels[r].size()
		var row := PackedFloat32Array()
		for c in picks:
			list.append(candidates[c])
			row.append(landing_costs[r][c] * size)
		choices.append(list)
		costs.append(row)
	# What each two neighbours' choices cost together, for the messages from each to the
	# other: by the receiver's choice, what each of the sender's costs with it
	var pair_costs := {}
	var keys := regions.borders.keys()
	var tables := []
	var sizes := PackedInt32Array()
	for key: Vector2i in keys:
		sizes.append(choices[key.x].size() * choices[key.y].size())
	for part: Array in shared(largest_first(sizes), _apart_tables.bind(keys, choices)):
		tables.append_array(part)
	for n in keys.size():
		var key: Vector2i = keys[n]
		var table: Array[PackedFloat32Array] = tables[n]
		pair_costs[Vector2i(key.y, key.x)] = table
		var turned: Array[PackedFloat32Array] = []
		for j in choices[key.y].size():
			var column := PackedFloat32Array()
			column.resize(table.size())
			for i in table.size():
				column[i] = table[i][j]
			turned.append(column)
		pair_costs[key] = turned
	# Messages from each region to each neighbour, about the neighbour's choices, by edge:
	# the region they're from and to, and the edges bringing the others' to the first
	var froms := PackedInt32Array()
	var tos := PackedInt32Array()
	var edge_of := {}
	for key: Vector2i in regions.borders:
		for edge: Vector2i in [key, Vector2i(key.y, key.x)]:
			edge_of[edge] = froms.size()
			froms.append(edge.x)
			tos.append(edge.y)
	var edges := froms.size()
	var into: Array[PackedInt32Array] = []
	var edge_tables: Array[Array] = []
	var messages: Array[PackedFloat32Array] = []
	for e in edges:
		var others := PackedInt32Array()
		for k: int in neighbours[froms[e]]:
			if k != tos[e]:
				others.append(edge_of[Vector2i(k, froms[e])])
		into.append(others)
		edge_tables.append(pair_costs[Vector2i(froms[e], tos[e])])
		messages.append(_zeros(choices[tos[e]].size()))
	var known := {"from": froms, "into": into, "tables": edge_tables, "costs": costs}
	for _round in ROUNDS:
		# Each round's messages are worked out from the last round's alone, so edges are
		# shared out among threads
		var updated: Array[PackedFloat32Array] = []
		for part: Array in Parallel.split(edges, MESSAGES_LEAST, _messages.bind(messages, known)):
			updated.append_array(part)
		messages = updated
	var picked: Array[Transform2D] = []
	for r in count:
		var belief := costs[r].duplicate()
		for k: int in neighbours[r]:
			var incoming := messages[edge_of[Vector2i(k, r)]]
			for i in belief.size():
				belief[i] += incoming[i]
		var best := 0
		for i in belief.size():
			if belief[i] < belief[best]:
				best = i
		picked.append(choices[r][best])
	return picked


## The messages along edges [param start] to [param end] (past the last) of the round after
## the one with [param messages], see [method _choose]; [param known] holds what's known of
## each edge: the region it's from, the edges into that region from the others, the table of
## what the two's choices cost together, and the regions' own costs
static func _messages(
	start: int, end: int, messages: Array[PackedFloat32Array], known: Dictionary
) -> Array[PackedFloat32Array]:
	var froms: PackedInt32Array = known["from"]
	var into: Array[PackedInt32Array] = known["into"]
	var tables: Array[Array] = known["tables"]
	var costs: Array[PackedFloat32Array] = known["costs"]
	var updated: Array[PackedFloat32Array] = []
	for e in range(start, end):
		var belief := costs[froms[e]].duplicate()
		for k in into[e]:
			var incoming := messages[k]
			for i in belief.size():
				belief[i] += incoming[i]
		var table: Array[PackedFloat32Array] = tables[e]
		var old := messages[e]
		var message := PackedFloat32Array()
		message.resize(old.size())
		var lowest := INF
		var size := belief.size()
		for j in message.size():
			var together := table[j]
			var best := INF
			for i in size:
				best = minf(best, belief[i] + together[i])
			message[j] = best
			lowest = minf(lowest, best)
		for j in message.size():
			message[j] = 0.5 * old[j] + 0.5 * (message[j] - lowest)
		updated.append(message)
	return updated


## For regions [param start] to [param end] (past the last), what [param candidates]
## landing them on the other key cost (see [method RegionMotions.cost]) and their best few
## of them, by their place among them, cheapest first: [code][best few, costs][/code], a
## list of each.
## Only the costs of candidates that might be among the best few are worked out: the others
## are given up on as soon as they cost more than the best few so far, and left at -1.
func _own_best(start: int, end: int, candidates: Array[Transform2D]) -> Array:
	if NativeKernels.kernels:
		return NativeKernels.own_best(self, start, end, candidates)
	var own: Array[PackedInt32Array] = []
	var landing_costs: Array[PackedFloat64Array] = []
	for r in range(start, end):
		var pixels := regions.pixels[r]
		var row := PackedFloat64Array()
		row.resize(candidates.size())
		# The lowest costs so far, cheapest first
		var lowest := PackedFloat64Array()
		var gave_up := false
		for c in candidates.size():
			var limit := lowest[OWN_CHOICES - 1] if lowest.size() >= OWN_CHOICES else INF
			var value := motions.cost_below(pixels, candidates[c], limit)
			if value > limit:
				row[c] = -1.0
				gave_up = true
				continue
			row[c] = value
			lowest.insert(lowest.bsearch(value), value)
			if lowest.size() > OWN_CHOICES:
				lowest.resize(OWN_CHOICES)
		var best := _cheapest(row, candidates, lowest[-1] if gave_up else INF, gave_up)
		if best.is_empty() and gave_up:
			# Candidates alike in cost could come out in another order than when every cost
			# is worked out: all are
			for c in candidates.size():
				if row[c] == -1.0:
					row[c] = motions.cost(r, candidates[c])
			best = _cheapest(row, candidates, INF, false)
		landing_costs.append(row)
		own.append(best)
	return [own, landing_costs]


## The best few of [param candidates] by their costs [param row], cheapest first, counting
## only those costing at most [param most] and known (not -1). Empty when two of those
## that aren't the same motion cost the same and [param ties] is true.
func _cheapest(
	row: PackedFloat64Array, candidates: Array[Transform2D], most: float, ties: bool
) -> PackedInt32Array:
	var scored: Array[Array] = []
	for c in candidates.size():
		if row[c] != -1.0 and not row[c] > most:
			scored.append([row[c], candidates[c], c])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var best := PackedInt32Array()
	if ties:
		for k in range(1, scored.size()):
			if scored[k][0] == scored[k - 1][0] and scored[k][1] != scored[k - 1][1]:
				return best
	for entry: Array in scored.slice(0, OWN_CHOICES):
		best.append(entry[2])
	return best


## For regions [param start] to [param end] (past the last), what their neighbours' best
## few of [param candidates] cost them where [param landing_costs] doesn't tell yet:
## [code][region, candidate, cost][/code] for each
func _missing_costs(
	start: int,
	end: int,
	candidates: Array[Transform2D],
	own: Array[PackedInt32Array],
	landing_costs: Array[PackedFloat64Array],
	neighbours: Array[Array]
) -> Array:
	var found := []
	for r in range(start, end):
		var row := landing_costs[r]
		var done := {}
		for k: int in neighbours[r]:
			for c in own[k].slice(0, SHARED_CHOICES):
				if row[c] == -1.0 and not done.has(c):
					done[c] = true
					found.append([r, c, motions.cost(r, candidates[c])])
	return found


## [method _apart_costs] for the bordering regions [param keys] [param start] to
## [param end] (past the last) say, choosing from [param choices]
func _apart_tables(start: int, end: int, keys: Array, choices: Array[Array]) -> Array:
	if NativeKernels.kernels:
		return NativeKernels.apart_tables(self, start, end, keys, choices)
	var tables := []
	for n in range(start, end):
		var key: Vector2i = keys[n]
		tables.append(_apart_costs(key.x, key.y, choices[key.x], choices[key.y]))
	return tables


## What neighbours [param r] and [param s] moving by each of their choices costs: how far
## each one's border, moved, ends up from the other's pixels, moved, times the border's
## length. Rows are [param r]'s choices.
func _apart_costs(r: int, s: int, r_choices: Array, s_choices: Array) -> Array[PackedFloat32Array]:
	var border := _spread(regions.borders[Vector2i(r, s)], BORDER_POINTS)
	var r_points := _spread(_points_of(r), REGION_POINTS)
	var s_points := _spread(_points_of(s), REGION_POINTS)
	var r_border: Array[PackedVector2Array] = []
	var r_moved: Array[PackedVector2Array] = []
	for motion: Transform2D in r_choices:
		r_border.append(motion * border)
		r_moved.append(motion * r_points)
	var s_border: Array[PackedVector2Array] = []
	var s_moved: Array[PackedVector2Array] = []
	for motion: Transform2D in s_choices:
		s_border.append(motion * border)
		s_moved.append(motion * s_points)
	var a := regions.colors[r] - regions.colors[s]
	var alike := exp(-(absf(a.x) + absf(a.y) + absf(a.z)) / ALIKE)
	var weight := (
		(APART_COST + (ALIKE_APART_COST - APART_COST) * alike)
		* regions.borders[Vector2i(r, s)].size()
	)
	var table: Array[PackedFloat32Array] = []
	for i in r_choices.size():
		var row := PackedFloat32Array()
		row.resize(s_choices.size())
		for j in s_choices.size():
			var gap := (
				0.5
				* (_mean_nearest(r_border[i], s_moved[j]) + _mean_nearest(s_border[j], r_moved[i]))
			)
			row[j] = weight * clampf(gap - 1.0, 0.0, GAP_CAP)
		table.append(row)
	return table


## The average, over [param points], of how far each is from the nearest of [param others]
static func _mean_nearest(points: PackedVector2Array, others: PackedVector2Array) -> float:
	var total := 0.0
	for point in points:
		var nearest := INF
		for spot in others:
			nearest = minf(nearest, point.distance_squared_to(spot))
		total += sqrt(nearest)
	return total / maxi(points.size(), 1)


func _points_of(r: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	for p in regions.pixels[r]:
		points.append(regions.point_of(p))
	return points


## At most [param most] of [param points], spread evenly through them
static func _spread(points: PackedVector2Array, most: int) -> PackedVector2Array:
	if points.size() <= most:
		return points
	var spread := PackedVector2Array()
	for k in most:
		spread.append(points[int(float(k) * (points.size() - 1) / (most - 1))])
	return spread


static func _zeros(size: int) -> PackedFloat32Array:
	var zeros := PackedFloat32Array()
	zeros.resize(size)
	return zeros
