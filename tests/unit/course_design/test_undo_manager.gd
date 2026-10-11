extends GameTest
## Undo and redo while building: a paint stroke is one action however many tiles
## it touched, a new action clears what could be redone, and the history keeps
## only the most recent actions.

var undo: UndoManager

func before_each() -> void:
	super()
	undo = autofree(UndoManager.new())

func test_stroke_keeps_every_tile_and_its_cost_as_one_action() -> void:
	undo.begin_stroke()
	undo.record_tile_change(Vector2i(2, 3), 0, 1)
	# A wood painted in the same stroke is one of those tiles: there is no second
	# layer of planted objects to remember alongside the ground any more.
	undo.record_tile_change(Vector2i(2, 4), TerrainTypes.Type.GRASS, TerrainTypes.Type.OAK)
	undo.record_stroke_cost(37)
	undo.end_stroke()
	var action := undo.undo()
	assert_eq(action.paid_cost, 37, "The stroke is refunded as a whole")
	assert_eq((action.changes as Array).size(), 2, "Both tiles belong to the one action")
	assert_eq(undo.redo(), action)

func test_an_empty_stroke_leaves_no_action() -> void:
	undo.begin_stroke()
	undo.record_stroke_cost(10)
	undo.end_stroke()
	assert_false(undo.can_undo(), "A stroke that changed nothing is not an action")

func test_a_change_outside_a_stroke_is_its_own_action() -> void:
	undo.record_tile_change(Vector2i(1, 1), TerrainTypes.Type.GRASS, TerrainTypes.Type.TEE_BOX)
	undo.record_walking_path(Vector2i(2, 2), true)
	assert_eq(undo.undo_stack.size(), 2)
	assert_eq(undo.undo_stack[1].type, "walking_paths")

func test_paths_laid_in_a_stroke_join_its_action() -> void:
	undo.begin_stroke()
	undo.record_walking_path(Vector2i(4, 4), true)
	undo.end_stroke()
	var action := undo.undo()
	assert_eq(action.type, "terrain")
	assert_eq(action.walking_paths, [{"position": Vector2i(4, 4), "added": true}])

func test_undo_then_redo_walks_the_history_and_a_new_action_clears_redo() -> void:
	undo.record_entity_placement("building", Vector2i(3, 3), "pro_shop", 500)
	undo.record_entity_placement("decoration", Vector2i(5, 5), "park_bench", 50)
	assert_eq(undo.undo().subtype, "park_bench", "The last action is undone first")
	assert_true(undo.can_redo())
	assert_eq(undo.redo().subtype, "park_bench")
	undo.undo()
	undo.record_entity_placement("decoration", Vector2i(6, 6), "fountain", 80)
	assert_false(undo.can_redo(), "A new action clears what could be redone")
	assert_eq(undo.undo().subtype, "fountain")
	assert_eq(undo.undo().subtype, "pro_shop", "The undone bench is gone from the history")

func test_nothing_to_undo_returns_an_empty_action() -> void:
	assert_eq(undo.undo(), {})
	assert_eq(undo.redo(), {})

func test_the_history_keeps_only_the_most_recent_actions() -> void:
	for i in range(UndoManager.MAX_UNDO_STACK + 5):
		undo.record_entity_placement("decoration", Vector2i(i, 0), "sundial", 10)
	assert_eq(undo.undo_stack.size(), UndoManager.MAX_UNDO_STACK)
	assert_eq(undo.undo_stack[0].grid_pos, Vector2i(5, 0), "The oldest actions fall off the end")

func test_clear_forgets_everything() -> void:
	undo.record_entity_placement("decoration", Vector2i(1, 1), "sundial", 10)
	undo.undo()
	undo.begin_stroke()
	undo.clear()
	assert_false(undo.can_undo())
	assert_false(undo.can_redo())
	undo.record_tile_change(Vector2i(1, 1), 0, 1)
	assert_true(undo.can_undo(), "A change after clear() is recorded on its own again")
