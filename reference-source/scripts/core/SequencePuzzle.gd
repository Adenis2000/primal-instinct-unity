class_name SequencePuzzle
extends RefCounted
## "Singing Stones": repeat the shown sequence. Pure logic (UI in PuzzleScreen).

var sequence: Array = []
var buttons: int = 4
var mistakes_left: int = 2
var pos: int = 0
var finished: bool = false
var success: bool = false

static func from_room(room: Dictionary) -> SequencePuzzle:
	var p := SequencePuzzle.new()
	p.sequence = room["sequence"].duplicate()
	p.buttons = int(room["buttons"])
	p.mistakes_left = int(room["mistakes"])
	return p

## Returns "ok" (correct, more to go), "done" (solved), "wrong" (mistake, replay), "fail" (out of mistakes).
func press(i: int) -> String:
	if finished:
		return "done" if success else "fail"
	if i == int(sequence[pos]):
		pos += 1
		if pos >= sequence.size():
			finished = true
			success = true
			return "done"
		return "ok"
	mistakes_left -= 1
	pos = 0
	if mistakes_left <= 0:
		finished = true
		success = false
		return "fail"
	return "wrong"
