extends GutTest


func test_autoload_exists_and_tests_never_start_it():
	var node := get_tree().root.get_node_or_null("ChessEngine")
	assert_true(node is UciEngine); assert_false(node.is_ready())
