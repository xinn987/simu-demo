## 实验室集成验证：实例化真实场景，并通过输入事件操作按钮与画布。
## 有图形设备时额外保存截图；无界面模式仍可验证控件、输入与暂停行为。
extends SceneTree

var _checks: int = 0
var _failures: int = 0


## 等待场景树准备完成再挂载实验室。
func _initialize() -> void:
	_run.call_deferred()


## 在真实界面中验证最关键的操作链，防止核心正常但交互未接通。
func _run() -> void:
	root.size = Vector2i(1120, 760)
	var scene: PackedScene = load("res://scenes/laboratory.tscn")
	var laboratory: Control = scene.instantiate()
	root.add_child(laboratory)
	await process_frame
	await process_frame
	var simulation: SandSimulation = laboratory.get("simulation")
	var view: GridView = laboratory.get_node("%GridView")
	_check(simulation.world.count_material(Materials.Id.SAND) == 800, "initial experiment has 800 sand cells")
	await _click_control(laboratory.get_node("%PauseButton"))
	var paused_step: int = simulation.step_count
	await physics_frame
	await physics_frame
	_check(laboratory.get("paused") and simulation.step_count == paused_step, "pause stops simulation")
	await _click_control(laboratory.get_node("%ClearButton"))
	_check(simulation.world.count_material(Materials.Id.SAND) == 0, "clear removes initial sand")
	_check(simulation.world.count_material(Materials.Id.WALL) == 0, "clear removes initial walls")
	await _click_control(laboratory.get_node("%WallButton"))
	_check(laboratory.get("selected_material") == Materials.Id.WALL, "wall tool is connected")
	var click_position: Vector2 = _cell_center(view, Vector2i(12, 12))
	_move_mouse(click_position)
	_send_button(click_position, MOUSE_BUTTON_LEFT, true)
	_send_button(click_position, MOUSE_BUTTON_LEFT, false)
	await process_frame
	_check(simulation.world.get_material(Vector2i(12, 12)) == Materials.Id.WALL, "quick click works without waiting for physics step")
	await _drag(_cell_center(view, Vector2i(20, 20)), _cell_center(view, Vector2i(35, 20)), MOUSE_BUTTON_LEFT)
	_check(simulation.world.get_material(Vector2i(28, 20)) == Materials.Id.WALL, "drag fills gap between sampled positions")
	await _drag(_cell_center(view, Vector2i(28, 20)), _cell_center(view, Vector2i(28, 20)), MOUSE_BUTTON_RIGHT)
	_check(simulation.world.get_material(Vector2i(28, 20)) == Materials.Id.AIR, "right button erases")
	await _click_control(laboratory.get_node("%SandButton"))
	await _drag(_cell_center(view, Vector2i(20, 20)), _cell_center(view, Vector2i(20, 20)), MOUSE_BUTTON_LEFT)
	_check(simulation.world.get_material(Vector2i(20, 20)) == Materials.Id.WALL, "sand brush cannot overwrite wall")
	await _drag(_cell_center(view, Vector2i(70, 12)), _cell_center(view, Vector2i(70, 12)), MOUSE_BUTTON_LEFT)
	_check(simulation.world.get_material(Vector2i(70, 12)) == Materials.Id.SAND, "paused world remains editable")
	await _click_control(laboratory.get_node("%PauseButton"))
	await physics_frame
	await physics_frame
	_check(not laboratory.get("paused") and simulation.step_count > 0, "resume advances simulation")
	await _click_control(laboratory.get_node("%PauseButton"))
	await _click_control(laboratory.get_node("%ResetButton"))
	_check(simulation.world.count_material(Materials.Id.SAND) == 800, "reset restores initial materials")
	_check(simulation.step_count == 0 and laboratory.get("paused"), "reset preserves pause and resets time")
	_check(view.local_to_cell(Vector2(-1, -1)) == GridView.NO_CELL, "outside canvas cannot paint")
	_check(view.local_to_cell(_cell_center(view, Vector2i(159, 89)) - view.global_position) == Vector2i(159, 89), "coordinate mapping reaches last cell")
	# 在较小窗口再次验证布局与坐标；不依赖截图推断输入是否正确。
	root.size = Vector2i(900, 600)
	await process_frame
	await process_frame
	var clear_button: Button = laboratory.get_node("%ClearButton")
	_check(root.get_visible_rect().encloses(clear_button.get_global_rect()), "toolbar fits smaller viewport")
	_check(view.local_to_cell(_cell_center(view, Vector2i(80, 45)) - view.global_position) == Vector2i(80, 45), "resized canvas retains coordinate mapping")
	await _save_screenshot("laboratory-small.png")
	root.size = Vector2i(1120, 760)
	await process_frame
	await process_frame
	await _click_control(laboratory.get_node("%PauseButton"))
	for frame in range(65):
		await physics_frame
	await _click_control(laboratory.get_node("%PauseButton"))
	await _save_screenshot("laboratory.png")
	print("Laboratory checks: %d, failures: %d" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


## 通过输入分发点击真实控件，验证信号连接和命中区域。
func _click_control(control: Control) -> void:
	var position: Vector2 = control.get_global_rect().get_center()
	_move_mouse(position)
	_send_button(position, MOUSE_BUTTON_LEFT, true)
	await process_frame
	_send_button(position, MOUSE_BUTTON_LEFT, false)
	await process_frame


## 保持按键跨越物理步，覆盖“按住投放”和连续笔划的实际路径。
func _drag(start: Vector2, finish: Vector2, button: MouseButton) -> void:
	_move_mouse(start)
	_send_button(start, button, true)
	await physics_frame
	await physics_frame
	_move_mouse(finish)
	await physics_frame
	await physics_frame
	_send_button(finish, button, false)
	await process_frame


## 输入事件更新 Godot 的鼠标状态，因此能覆盖视图中的按键检测。
func _send_button(position: Vector2, button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = position
	event.global_position = position
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


## 模拟指针移动；不移动操作系统鼠标。
func _move_mouse(position: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = position
	event.global_position = position
	Input.parse_input_event(event)


## 使用视图实际布局计算格子中心，避免把窗口分辨率写死在交互验证里。
func _cell_center(view: GridView, cell: Vector2i) -> Vector2:
	var rect: Rect2 = view.get_canvas_rect()
	return view.global_position + rect.position + (Vector2(cell) + Vector2(0.5, 0.5)) * rect.size / Vector2(160, 90)


## 截图只在真正绘制后读取；headless 的空渲染设备不提供像素。
func _save_screenshot(file_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory: String = ProjectSettings.globalize_path("res://.godot/verification")
	DirAccess.make_dir_recursive_absolute(directory)
	var result: Error = root.get_texture().get_image().save_png(directory.path_join(file_name))
	_check(result == OK, "screenshot saved: " + file_name)


## 一次保留所有失败，进程退出码供命令行调用判断。
func _check(condition: bool, description: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		push_error("FAIL: " + description)
