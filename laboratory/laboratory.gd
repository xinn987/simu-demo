## 实验室入口：组装模拟与显示，处理工具选择、场景重置和运行暂停。
## 只有此层依赖具体界面节点；模拟核心可以在未来的工厂场景中直接复用。
extends Control

## 初期固定为小网格，优先让规则可验证；屏幕像素与模拟格子不是一一对应。
const WORLD_SIZE := Vector2i(160, 90)
## 固定初始种子让重置后的无输入实验可复现。
const EXPERIMENT_SEED: int = 20261006

var simulation: SandSimulation
var selected_material: int = Materials.Id.SAND
var paused: bool = false

@onready var grid_view: GridView = %GridView
@onready var sand_button: Button = %SandButton
@onready var wall_button: Button = %WallButton
@onready var erase_button: Button = %EraseButton
@onready var pause_button: Button = %PauseButton
@onready var brush_size: SpinBox = %BrushSize


## 在场景就绪后连接依赖，避免全局单例或隐藏的节点路径依赖进入核心。
func _ready() -> void:
	# 工具栏保持一行；限制最小窗口，避免控件被挤出可操作区域。
	get_window().min_size = Vector2i(900, 600)
	simulation = SandSimulation.new(WORLD_SIZE, EXPERIMENT_SEED)
	grid_view.bind_world(simulation.world)
	grid_view.stroke_requested.connect(_on_stroke_requested)
	sand_button.pressed.connect(_select_material.bind(Materials.Id.SAND))
	wall_button.pressed.connect(_select_material.bind(Materials.Id.WALL))
	erase_button.pressed.connect(_select_material.bind(Materials.Id.AIR))
	pause_button.toggled.connect(_set_paused)
	%ResetButton.pressed.connect(_reset_experiment)
	%ClearButton.pressed.connect(_clear_experiment)
	brush_size.value_changed.connect(_on_brush_size_changed)
	_reset_experiment()
	_select_material(Materials.Id.SAND)


## Godot 的固定物理步只负责调度；核心本身不依赖 SceneTree。
## 暂停仅停止材料演化，画笔仍可用于布置实验条件。
func _physics_process(_delta: float) -> void:
	if not paused:
		simulation.step()


## 快捷键只处理未被输入框消费的事件，编辑笔刷数字时不会误切换材料。
func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_1:
			_select_material(Materials.Id.SAND)
		KEY_2:
			_select_material(Materials.Id.WALL)
		KEY_3:
			_select_material(Materials.Id.AIR)
		KEY_SPACE:
			pause_button.button_pressed = not paused
		_:
			return
	get_viewport().set_input_as_handled()


## 仅改变当前工具，不直接改变世界。
func _select_material(material_id: int) -> void:
	selected_material = material_id
	sand_button.set_pressed_no_signal(material_id == Materials.Id.SAND)
	wall_button.set_pressed_no_signal(material_id == Materials.Id.WALL)
	erase_button.set_pressed_no_signal(material_id == Materials.Id.AIR)


## 运行状态属于实验室，不属于材料数据；无需暂停整棵场景树。
func _set_paused(value: bool) -> void:
	paused = value
	pause_button.text = "继续" if paused else "暂停"


## 笔刷设置由实验室拥有，视图只使用它画轮廓。
func _on_brush_size_changed(value: float) -> void:
	grid_view.brush_radius = int(value)
	grid_view.queue_redraw()


## 连接相邻采样点，使用圆形笔刷写入；右键始终擦除。
func _on_stroke_requested(from_cell: Vector2i, to_cell: Vector2i, erase: bool) -> void:
	var material_id: int = Materials.Id.AIR if erase else selected_material
	var distance: Vector2i = to_cell - from_cell
	var sample_count: int = maxi(absi(distance.x), absi(distance.y))
	for sample in range(sample_count + 1):
		var weight: float = float(sample) / maxi(sample_count, 1)
		var center := Vector2i(Vector2(from_cell).lerp(Vector2(to_cell), weight).round())
		_paint_circle(center, material_id)


## 画笔是外部编辑：沙只填充空位，墙可覆盖已有材料，擦除明确删除材料。
func _paint_circle(center: Vector2i, material_id: int) -> void:
	var radius: int = grid_view.brush_radius
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			if x * x + y * y > radius * radius:
				continue
			var cell: Vector2i = center + Vector2i(x, y)
			if material_id == Materials.Id.SAND and simulation.world.get_material(cell) != Materials.Id.AIR:
				continue
			simulation.world.set_material(cell, material_id)


## 一个简单的双平台落沙场景，用来验证支撑、缺口和堆积，无需额外场景系统。
func _reset_experiment() -> void:
	grid_view.cancel_stroke()
	simulation.reset(EXPERIMENT_SEED)
	for x in range(28, 72):
		simulation.world.set_material(Vector2i(x, 48), Materials.Id.WALL)
	for x in range(88, 132):
		simulation.world.set_material(Vector2i(x, 48), Materials.Id.WALL)
	for y in range(10, 26):
		for x in range(55, 105):
			simulation.world.set_material(Vector2i(x, y), Materials.Id.SAND)


## 清空保留封闭边界与当前暂停状态，便于从空白开始布置实验。
func _clear_experiment() -> void:
	grid_view.cancel_stroke()
	simulation.reset(EXPERIMENT_SEED)
