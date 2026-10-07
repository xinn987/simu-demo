## 网格视图：把材料状态变成纹理，并将画布内的鼠标操作转成格子笔划。
## 此处不修改材料，也不决定运动规则；实验室控制器负责处理笔划信号。
class_name GridView
extends Control

signal stroke_requested(from_cell: Vector2i, to_cell: Vector2i, erase: bool)

## 显示颜色不参与物理规则，修改配色不会改变模拟结果。
const MATERIAL_COLORS: Array[Color] = [
	Color("111820"), Color("edbd73"), Color("8196aa")
]
## 网格之外的哨兵坐标，代表当前没有可继续连接的笔划。
const NO_CELL := Vector2i(-1, -1)

var brush_radius: int = 2
var _world: GridWorld
var _image: Image
var _texture: ImageTexture
var _rendered_revision: int = -1
var _drawing: bool = false
var _erase: bool = false
var _last_cell: Vector2i = NO_CELL
## 使用 GUI 事件提供的局部坐标，使绘制与命中检测共用同一坐标来源。
var _pointer_position := Vector2(-1, -1)


## 绑定模拟数据，显示层只读取同一个世界，不维护第二份材料状态。
func bind_world(world: GridWorld) -> void:
	_world = world
	_image = Image.create(world.width, world.height, false, Image.FORMAT_RGBA8)
	_texture = ImageTexture.create_from_image(_image)
	_rendered_revision = -1
	refresh_texture()


## 静止世界无需重复生成纹理；鼠标移动仍可独立更新笔刷轮廓。
func _process(_delta: float) -> void:
	refresh_texture()


## 按住鼠标可以持续投放沙；只允许从画布内开始的笔划，避免点击工具栏时误绘。
func _physics_process(_delta: float) -> void:
	if not _drawing:
		return
	var button: MouseButton = MOUSE_BUTTON_RIGHT if _erase else MOUSE_BUTTON_LEFT
	if not Input.is_mouse_button_pressed(button):
		cancel_stroke()
		return
	var cell: Vector2i = local_to_cell(_pointer_position)
	if cell == NO_CELL:
		_last_cell = NO_CELL
		return
	var start: Vector2i = cell if _last_cell == NO_CELL else _last_cell
	stroke_requested.emit(start, cell, _erase)
	_last_cell = cell


## 输入只转换坐标与笔划意图；拖动在固定步中采样并连接，避免快速拖动留下断点。
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_pointer_position = event.position
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed and local_to_cell(event.position) != NO_CELL:
				_drawing = true
				_erase = event.button_index == MOUSE_BUTTON_RIGHT
				_last_cell = local_to_cell(event.position)
				# 点击立即生效，即使按下与松开发生在同一个物理步之间。
				stroke_requested.emit(_last_cell, _last_cell, _erase)
			elif not event.pressed and event.button_index == (MOUSE_BUTTON_RIGHT if _erase else MOUSE_BUTTON_LEFT):
				cancel_stroke()
			accept_event()
	queue_redraw()


## 窗口失焦或布局改变时也更新笔刷显示，并取消未结束的输入。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_pointer_position = Vector2(-1, -1)
		cancel_stroke()
	elif what == NOTIFICATION_MOUSE_EXIT or what == NOTIFICATION_RESIZED:
		_pointer_position = Vector2(-1, -1)
		_last_cell = NO_CELL
		queue_redraw()


## 结束笔划，禁止离开画布后把两段操作跨空白区域连接起来。
func cancel_stroke() -> void:
	_drawing = false
	_last_cell = NO_CELL
	queue_redraw()


## 小网格先采用完整纹理更新；以后通过性能测量决定是否引入分块脏区。
func refresh_texture() -> void:
	if _world == null or _rendered_revision == _world.revision:
		return
	for y in range(_world.height):
		for x in range(_world.width):
			_image.set_pixel(x, y, MATERIAL_COLORS[_world.get_material(Vector2i(x, y))])
	_texture.update(_image)
	_rendered_revision = _world.revision
	queue_redraw()


## 使用整数倍缩放保持像素边缘清晰；极小窗口才退回非整数缩放。
func get_canvas_rect() -> Rect2:
	if _world == null:
		return Rect2()
	var grid_size := Vector2(_world.width, _world.height)
	var scale_factor: float = minf(size.x / grid_size.x, size.y / grid_size.y)
	if scale_factor >= 1.0:
		scale_factor = floorf(scale_factor)
	var draw_size: Vector2 = grid_size * scale_factor
	return Rect2((size - draw_size) * 0.5, draw_size)


## 绘制和输入共用同一个矩形，保证窗口缩放后鼠标仍对准正确格子。
func local_to_cell(local_position: Vector2) -> Vector2i:
	var canvas_rect: Rect2 = get_canvas_rect()
	if not canvas_rect.has_point(local_position) or canvas_rect.size.x <= 0.0:
		return NO_CELL
	var relative: Vector2 = (local_position - canvas_rect.position) / canvas_rect.size
	return Vector2i(floori(relative.x * _world.width), floori(relative.y * _world.height))


## 一张纹理绘制整个世界，避免每格一个节点或一次绘制调用。
func _draw() -> void:
	if _texture == null:
		return
	var canvas_rect: Rect2 = get_canvas_rect()
	draw_texture_rect(_texture, canvas_rect, false)
	draw_rect(canvas_rect.grow(1.0), Color("405164"), false, 1.0)
	var cell: Vector2i = local_to_cell(_pointer_position)
	if cell != NO_CELL:
		var pixel_scale: float = canvas_rect.size.x / _world.width
		var center: Vector2 = canvas_rect.position + (Vector2(cell) + Vector2(0.5, 0.5)) * pixel_scale
		draw_circle(center, (brush_radius + 0.5) * pixel_scale, Color(1, 1, 1, 0.65), false, 1.0)
