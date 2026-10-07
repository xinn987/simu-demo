## 模拟核心：每次 step() 恰好推进一步，不读取帧率、鼠标或场景树。
## 当前只有向下运动的沙；加入水平流动或上升气体时必须重新设计更新防重。
class_name SandSimulation
extends RefCounted

var world: GridWorld
var step_count: int = 0
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


## 独立随机数发生器避免其他游戏逻辑干扰实验复现。
func _init(world_size: Vector2i, random_seed: int = 1) -> void:
	world = GridWorld.new(world_size)
	_random.seed = random_seed


## 从下往上更新：沙的新位置已经被扫描过，因此一颗沙每步最多下移一行。
## 每步交替横向扫描方向，斜落选择再用固定种子的随机数减少方向偏差。
func step() -> void:
	var scan_left_to_right: bool = step_count % 2 == 0
	for y in range(world.height - 2, -1, -1):
		for column in range(world.width):
			var x: int = column if scan_left_to_right else world.width - 1 - column
			var cell := Vector2i(x, y)
			if world.get_material(cell) == Materials.Id.SAND:
				_update_sand(cell)
	step_count += 1


## 清空并恢复随机种子；相同初始条件和相同操作顺序会重复相同结果。
func reset(random_seed: int) -> void:
	world.clear()
	step_count = 0
	_random.seed = random_seed


## 下方优先；受阻时尝试两个斜下方，全部失败则保留原位。
func _update_sand(cell: Vector2i) -> void:
	if world.try_move_to_empty(cell, cell + Vector2i.DOWN):
		return
	var first_direction: int = -1 if _random.randi_range(0, 1) == 0 else 1
	if world.try_move_to_empty(cell, cell + Vector2i(first_direction, 1)):
		return
	world.try_move_to_empty(cell, cell + Vector2i(-first_direction, 1))
