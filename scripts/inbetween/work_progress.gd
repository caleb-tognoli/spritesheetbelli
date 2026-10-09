class_name WorkProgress
extends RefCounted
## How far a long piece of work running on another thread got, and whether it should
## stop, see [method InBetween.prepare]

var done := 0
var total := 0
## Set to stop the work
var cancelled := false


## How much is done, from 0 to 1
func get_ratio() -> float:
	return float(done) / total if total > 0 else 0.0
