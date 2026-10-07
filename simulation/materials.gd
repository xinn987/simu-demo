## 材料编号表：世界只保存紧凑的编号，不为每个格子创建对象。
## 固定属性以后集中加在这里；本轮只定义空气、沙和不可移动的墙。
class_name Materials
extends RefCounted

## 编号需要保持稳定，未来存档也会引用它们；空气必须为 0。
enum Id { AIR, SAND, WALL }


## 拦截未知编号，避免实验室把无效材料写入世界。
static func is_valid(material_id: int) -> bool:
	return material_id >= Id.AIR and material_id <= Id.WALL
