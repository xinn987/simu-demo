## 网格是唯一的材料状态来源，不依赖场景节点、输入或渲染。
## 二维坐标按 index = y * width + x 存入一维数组。
class_name GridWorld
extends RefCounted

## 尺寸创建后保持不变，调整实验尺寸时重新创建世界。
var width: int
var height: int
## 显示层只在版本发生变化时上传纹理；版本不代表模拟步数。
var revision: int = 0
var _cells: PackedByteArray = PackedByteArray()


## 创建一个空世界；每格只占一个材料编号字节。
func _init(world_size: Vector2i) -> void:
	assert(world_size.x > 0 and world_size.y > 0, "网格尺寸必须大于零")
	width = world_size.x
	height = world_size.y
	_cells.resize(width * height)
	_cells.fill(Materials.Id.AIR)


## 所有读写都使用同一套边界判断。
func contains(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < width and cell.y >= 0 and cell.y < height


## 网格外视为墙，形成封闭实验边界；不在数组里额外存储边界。
func get_material(cell: Vector2i) -> int:
	if not contains(cell):
		return Materials.Id.WALL
	return _cells[cell.y * width + cell.x]


## 实验操作可以覆盖材料，这是显式编辑，不属于守恒的内部运动。
func set_material(cell: Vector2i, material_id: int) -> bool:
	if not contains(cell) or not Materials.is_valid(material_id):
		return false
	var index: int = cell.y * width + cell.x
	if _cells[index] == material_id:
		return false
	_cells[index] = material_id
	revision += 1
	return true


## 原地提交一次完整搬运，确保来源与目标同时改变，不复制或覆盖材料。
## 能否尝试这种运动由规则层决定；这里仅保证空位搬运的基本约束。
func try_move_to_empty(source: Vector2i, destination: Vector2i) -> bool:
	if not contains(source) or not contains(destination):
		return false
	var source_index: int = source.y * width + source.x
	var destination_index: int = destination.y * width + destination.x
	if _cells[source_index] == Materials.Id.AIR or _cells[destination_index] != Materials.Id.AIR:
		return false
	_cells[destination_index] = _cells[source_index]
	_cells[source_index] = Materials.Id.AIR
	revision += 1
	return true


## 清空由实验室明确触发，不计作自然消失。
func clear() -> void:
	_cells.fill(Materials.Id.AIR)
	revision += 1


## 数量统计供断点、日志与守恒验证使用，不必常驻实验室界面。
func count_material(material_id: int) -> int:
	return _cells.count(material_id)
