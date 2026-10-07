## 无界面的行为验证：只依赖模拟核心，可作为以后扩展材料时的回归基准。
## 运行：Godot --headless --path 项目目录 --script res://tests/test_simulation.gd
extends SceneTree

var _checks: int = 0
var _failures: int = 0


## 每项验证对应一个容易出错的外部行为，而不是复写实现过程。
func _initialize() -> void:
	_test_single_step()
	_test_support_removal()
	_test_contested_destination()
	_test_closed_boundary()
	_test_conservation_and_replay()
	_test_invalid_edits()
	print("Simulation checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## 一步只能下降一行，不能沿原地更新链连续穿过整个世界。
func _test_single_step() -> void:
	var simulation := SandSimulation.new(Vector2i(7, 7), 11)
	simulation.world.set_material(Vector2i(3, 1), Materials.Id.SAND)
	simulation.step()
	_check(simulation.world.get_material(Vector2i(3, 2)) == Materials.Id.SAND, "one row per step")
	_check(simulation.world.count_material(Materials.Id.SAND) == 1, "movement preserves grain")
	_check(simulation.step_count == 1, "one explicit simulation step")


## 横向完整的支撑面阻挡沙；撤去支撑后，无须重新投放就恢复下落。
func _test_support_removal() -> void:
	var simulation := SandSimulation.new(Vector2i(7, 7), 11)
	for x in range(7):
		simulation.world.set_material(Vector2i(x, 3), Materials.Id.WALL)
	simulation.world.set_material(Vector2i(3, 2), Materials.Id.SAND)
	for step in range(5):
		simulation.step()
	_check(simulation.world.get_material(Vector2i(3, 2)) == Materials.Id.SAND, "wall supports sand")
	simulation.world.set_material(Vector2i(3, 3), Materials.Id.AIR)
	simulation.step()
	_check(simulation.world.get_material(Vector2i(3, 3)) == Materials.Id.SAND, "removed support resumes falling")


## 两颗沙只共享一个可达空位，顺序占位应保留失败者而不是覆盖或复制。
func _test_contested_destination() -> void:
	var simulation := SandSimulation.new(Vector2i(5, 5), 11)
	for x in [0, 1, 3, 4]:
		simulation.world.set_material(Vector2i(x, 2), Materials.Id.WALL)
	simulation.world.set_material(Vector2i(1, 1), Materials.Id.SAND)
	simulation.world.set_material(Vector2i(3, 1), Materials.Id.SAND)
	simulation.step()
	_check(simulation.world.get_material(Vector2i(2, 2)) == Materials.Id.SAND, "one winner occupies shared target")
	_check(simulation.world.count_material(Materials.Id.SAND) == 2, "contention preserves both grains")
	_check(simulation.world.count_material(Materials.Id.WALL) == 4, "contention does not overwrite walls")


## 边缘与角落也使用封闭边界，不允许索引绕回另一行或流出世界。
func _test_closed_boundary() -> void:
	var simulation := SandSimulation.new(Vector2i(5, 5), 11)
	simulation.world.set_material(Vector2i(0, 0), Materials.Id.SAND)
	simulation.world.set_material(Vector2i(4, 0), Materials.Id.SAND)
	for step in range(20):
		simulation.step()
	_check(simulation.world.count_material(Materials.Id.SAND) == 2, "closed edges preserve grains")
	_check(simulation.world.get_material(Vector2i(0, 4)) == Materials.Id.SAND, "left grain reaches floor")
	_check(simulation.world.get_material(Vector2i(4, 4)) == Materials.Id.SAND, "right grain reaches floor")


## 多步堆积同时验证守恒、墙体稳定和相同种子的可重复性。
func _test_conservation_and_replay() -> void:
	var first := SandSimulation.new(Vector2i(32, 24), 1234)
	var second := SandSimulation.new(Vector2i(32, 24), 1234)
	_fill_replay_scene(first.world)
	_fill_replay_scene(second.world)
	var initial_sand: int = first.world.count_material(Materials.Id.SAND)
	var initial_walls: int = first.world.count_material(Materials.Id.WALL)
	for step in range(80):
		first.step()
		second.step()
	_check(first.world.count_material(Materials.Id.SAND) == initial_sand, "sand conserved after settling")
	_check(first.world.count_material(Materials.Id.WALL) == initial_walls, "walls remain unchanged")
	_check(_worlds_match(first.world, second.world), "same seed reproduces same state")
	first.reset(1234)
	_check(first.step_count == 0 and first.world.count_material(Materials.Id.SAND) == 0, "reset clears state and time")
	_fill_replay_scene(first.world)
	for step in range(80):
		first.step()
	_check(_worlds_match(first.world, second.world), "reset also restores random sequence")


## 未知编号与越界编辑应被拒绝；无变化的编辑不触发纹理刷新。
func _test_invalid_edits() -> void:
	var world := GridWorld.new(Vector2i(3, 3))
	var initial_revision: int = world.revision
	_check(not world.set_material(Vector2i(-1, 0), Materials.Id.SAND), "out of bounds edit rejected")
	_check(not world.set_material(Vector2i(1, 1), 255), "unknown material rejected")
	_check(not world.set_material(Vector2i(1, 1), Materials.Id.AIR), "unchanged edit rejected")
	_check(world.revision == initial_revision, "rejected edits do not dirty world")
	world.set_material(Vector2i(0, 0), Materials.Id.SAND)
	_check(not world.try_move_to_empty(Vector2i(0, 0), Vector2i(-1, 0)), "movement cannot leave boundary")


## 两个平台与一个缺口产生足够多的斜落竞争，用于重复性验证。
func _fill_replay_scene(world: GridWorld) -> void:
	for x in range(2, 30):
		if x != 15 and x != 16:
			world.set_material(Vector2i(x, 14), Materials.Id.WALL)
	for y in range(1, 9):
		for x in range(8, 24):
			world.set_material(Vector2i(x, y), Materials.Id.SAND)


## 对比材料分布，而不是只对比数量，避免遗漏随机序列或扫描顺序的变化。
func _worlds_match(first: GridWorld, second: GridWorld) -> bool:
	for y in range(first.height):
		for x in range(first.width):
			if first.get_material(Vector2i(x, y)) != second.get_material(Vector2i(x, y)):
				return false
	return true


## 保留所有失败项，方便一次运行定位多个行为问题。
func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
