# SimuDemo 材料实验室

用 Godot 4.7 构建一个可验证的像素材料模拟核心。当前实现空气、沙、墙和基础实验操作；后续先扩展材料规律，再发展自动化设施与生产流水线。

## 技术参考

- [Jason 落沙系列：阅读笔记与项目参考](docs/references/jason-falling-sand-series.md)：整理基础落沙、性能与速度、烟雾与燃烧三篇文章，区分原文方法、当前实现和后续候选优化，并列出适用条件与验证场景。

这些笔记用于后续逐项讨论和验证，不表示文中方案已经实现。

## 运行与操作

在 Godot 中导入本目录的 `project.godot`，按 **F6** 运行实验室场景，或按 **F5** 运行项目。

- 左键：使用当前材料绘制；按住可以持续投放沙。
- 右键：擦除材料。
- `1 / 2 / 3`：选择沙、墙、擦除。
- 空格或“暂停”：暂停/继续材料运动。暂停时仍然可以布置材料。
- “重置”：恢复初始双平台落沙实验及其随机种子，保留暂停状态。
- “清空”：清空材料，保留封闭边界及暂停状态。

实验世界为 160 × 90 格，显示按窗口大小进行缩放。窗口像素和模拟格子不是同一个概念。世界外部不可进入，因此沙会停在底边；侧边与底边不需要额外存一圈墙。

画笔属于外部编辑：沙只放入空位；墙可以覆盖沙；擦除会删除材料。这些数量变化是人工操作，不是自然模拟中的守恒错误。

## 目录与职责

```text
simu-demo/
├── project.godot                 # 项目设置与主场景入口
├── scenes/
│   └── laboratory.tscn           # 可在 Godot 编辑器中调整的界面节点树
├── laboratory/
│   └── laboratory.gd            # 组装、工具操作、暂停和初始实验布置
├── simulation/
│   ├── materials.gd             # 稳定的材料编号与合法性判断
│   ├── grid_world.gd            # 材料数组、边界、读写和完整搬运
│   └── sand_simulation.gd       # 一步模拟的扫描顺序与沙的移动规则
├── rendering/
│   └── grid_view.gd             # 网格纹理、缩放和鼠标坐标转换
├── docs/
│   └── references/              # 技术资料笔记与后续优化参考
└── tests/
    ├── test_simulation.gd       # 无界面行为验证
    └── test_laboratory.gd       # 真实场景的输入、布局与运行验证
```

`simulation` 中的三个类都继承 `RefCounted`，不是场景节点。它们不读取鼠标，不查找界面，也不依赖游戏帧率。未来的工厂场景可以创建同样的模拟对象，不必继承实验室。

`laboratory.tscn` 保存具体界面结构；控制脚本通过唯一节点名（例如 `%GridView`）找到控件。按钮、容器和布局都可以在 Godot 编辑器中直接查看。当前没有 Autoload、事件总线、通用机器基类或插件式规则框架，因为还没有需要它们的实际场景。

## 一次更新怎样流过代码

1. Godot 的固定物理步调用 `laboratory.gd::_physics_process()`。
2. 若没有暂停，控制器调用 `SandSimulation.step()`。
3. 模拟器从下往上读取 `GridWorld`，对沙调用 `_update_sand()`。
4. 沙尝试向下、斜下移动；`try_move_to_empty()` 在检查通过后同时清空来源、填入目标。
5. 世界的 `revision` 增加。显示层在 `_process()` 中发现版本改变，更新纹理。

输入走另一条路径：`GridView` 识别画布内开始的鼠标笔划 → 发出 `stroke_requested` 信号 → 实验室连接采样点并写入圆形笔刷。视图不直接改变材料规则。

当前沿用 Godot 默认的每秒 60 次固定物理步，一步最多下落一行。严重卡顿时并不承诺维持真实时间速度，也还没有加速度或连续速度模型。模拟步与显示帧分离，但两者目前仍在主线程执行。

## 建议阅读顺序与断点

1. `materials.gd`：认识三个材料编号。
2. `grid_world.gd`：理解 `y * width + x` 如何把二维坐标映射到一维数组。
3. `sand_simulation.gd`：先看 `_update_sand()` 的三次移动尝试，再看 `step()` 的扫描顺序。
4. `laboratory.gd`：看 `_ready()` 怎样组装对象，`_physics_process()` 怎样调度一步。
5. 最后看 `grid_view.gd`：理解状态如何变成纹理，以及鼠标如何换算成格子。

适合在 `_update_sand()` 中给特定 `cell` 设置条件断点，并进入 `try_move_to_empty()` 观察来源和目标两个索引。`world.count_material(Materials.Id.SAND)` 可以用于断点求值或临时日志；无需为学习再制作一套调试面板。

## 当前规则的边界

- 只有沙会运动，墙永远不动。沙可下落或斜落，没有惯性、速度、温度或化学反应。
- 采用单线程原地更新，先占到目标位置的沙获胜。没有双缓冲或并行写入。
- 从下往上扫描保证当前沙每步最多下降一行。**这只适用于当前向下运动的规则**；加入水平水流、上升气体或密度交换时，需要显式防止同一材料重复更新。
- 横向扫描方向每步交替，斜落优先方向由独立随机数决定。这减少固定方向偏差，但不是严格物理对称或精确休止角模型。
- 相同种子、初始材料和逐步输入序列在当前实现中可复现。实时鼠标操作尚未录制，不承诺跨 Godot 版本随机序列一致。
- 当前每步扫描全图，变化时上传完整纹理。活跃区块、休眠、线程和原生扩展都留待性能测量后再引入。

材料编号使用一个字节，当前容量足够；增加材料时同时维护编号合法性、显示颜色与对应行为。热量、液体量等以后可以按需要增加独立数组，不必把每格改成一个节点。

## 行为验证

首次导入由 Godot 编辑器完成全局类扫描。命令行也可以先运行：

```powershell
& 'E:\Program Files\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe' --headless --editor --path . --import --quit
New-Item -ItemType Directory -Path '.godot/verification' -Force | Out-Null
$verificationDirectory = (Resolve-Path '.godot/verification').Path
& 'E:\Program Files\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe' --headless --path . --log-file "$verificationDirectory/simulation.log" --script res://tests/test_simulation.gd
& 'E:\Program Files\Godot\Godot_v4.7-stable_win64.exe\Godot_v4.7-stable_win64.exe' --path . --log-file "$verificationDirectory/laboratory.log" --script res://tests/test_laboratory.gd
```

测试关注单步移动、支撑移除、争抢同一空位、封闭边界、数量守恒、固定种子复现和非法编辑。实验室负责可见的现象验证；自动测试负责在以后修改规则时尽早发现基本行为回退。

图形模式的实验室测试会打开一个临时窗口、注入 Godot 输入事件并自动退出，将两种窗口尺寸的截图存入 `.godot/verification`。它不会操作系统鼠标。加入 `--headless` 则跳过截图。该目录已被现有 `.gitignore` 忽略。

受限环境下，Godot 可能无法写入默认用户日志或着色器缓存，所以测试命令明确把日志写入项目目录。当前环境还会输出系统根证书读取警告；这些环境警告应与脚本解析错误、断言失败分开判断。
