# Vortex（macOS 任务监督器 + 活动监视器）

Vortex 是一个 Swift/macOS 原生悬浮工作台，提供：
- 任务管理监督（任务进度、到点提醒、未完成提醒）
- 活动监视（近期活跃应用、快速激活）
- Safari/Chrome 标签页活动读取（授权后）
- 类 CodeIsland 的边缘吸附 + 收纳胶囊 + 渐进渐出显示

## 运行与构建

```bash
cd Vortex
xcodebuild -project Vortex.xcodeproj -scheme Vortex -destination 'platform=macOS' build
```

## 当前交互能力

1. 应用启动默认可直接贴边收纳（可在 Settings 关闭“Launch docked”）。  
2. 支持拖动到任意位置；鼠标移开后按策略自动回吸附（Top 或左右最近边）。  
3. 收纳后显示轻量预览（待办数量/活跃状态/设置入口）。  
4. Activity 分为 **Recent apps** 与 **Recent web pages**。  
5. 点击 Recent web pages 会激活 Safari/Chrome **已有标签页**（不新开页面）。  
6. Tasks 页支持“球形 +”打开任务新增页：可设置截止/每日、优先级、提醒频率（每小时/每天/每周），时间采用可输入文本（`YYYY-MM-DD` + `HH:mm`）。  
7. 任务列表按优先级排序，并以颜色/符号展示优先级。  
8. Settings 支持中英文切换，并可调：默认吸附边、启动是否贴边、自动回吸附、收纳/回吸附延时、动画时长、活动刷新间隔、recent 条数。  

## 性能优化记录（本轮）

1. **吸附逻辑降频**：从高频轮询改为窗口移动事件驱动 + 延迟评估，减少主线程压力。  
2. **活动监控优化**：引入应用激活通知驱动，降低全量扫描频率；避免重复启动跟踪。  
3. **图标缓存**：活动监控缓存 App Icon，减少重复图像解码。  
4. **浏览器读取缓存**：Safari/Chrome 标签页读取加入短 TTL 缓存，减少 AppleScript 压力。  
5. **格式化开销优化**：任务日期格式器改为静态复用，避免列表渲染重复创建。  

## 模块结构

- `App/`：应用入口、菜单、主窗口管理
- `Features/`：任务页、活动页、主界面与设置页
- `Core/Windowing`：吸附/收纳/展开控制器
- `Core/ActivityTracking`：应用活动与浏览器标签采集
- `Core/Reminder`：通知调度
- `Data/`：SwiftData 模型

## 权限说明

- 通知权限：任务提醒
- Apple Events / 自动化：浏览器标签活动读取（Safari/Chrome）
