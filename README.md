# lol-copilot

英雄联盟战绩助手。

- UI：PySide6 + [FluentUI-QML](https://github.com/zhuzichu520/PySide6-FluentUI-QML)
- 连接：LCU（League Client Update）本地 HTTPS + WebSocket
- 数据源（推荐/出装）：OP.GG

## 功能

**战绩**
- 我的生涯：段位卡片（单双/灵活/斗魂）+ 最近 20 场彩色英雄条 + 快速操作
- 最近战绩：20 / 50 / 100 场加载，按模式筛选（单双/灵活/匹配/大乱斗/斗魂/人机/自定义）
- 对局详情：10 人完整信息，英雄头像 + 召唤师技能 + 符文徽章 + 7 件装备 + 伤害条 + KDA/评分/MVP/ACE，双方团队统计对比（击杀·金币·塔·龙·男爵）
- 斗魂竞技场支持：用海克斯强化图标（按稀有度上色）替代符文显示
- 召唤师搜索与主页：按名字 / Riot ID / 全局别名三级查找，点击历史对局任一玩家直接打开对方主页

**选人阶段（实时）**
- 双方 10 人卡片：英雄头像 + 位置图标 + 段位徽章 + 最近 10 场 W/L 点阵 + 平均 KDA
- Pre-group 开黑组检测（3+ 同队出现自动用彩色标记）
- 禁用英雄带 × 角标展示

**辅助**
- 自动接受对局 / 自动禁用 / 自动选择（英雄优先级可视化选择器）
- 托盘一键暂停与恢复所有自动动作
- 英雄池统计（场次 / 胜率 / KDA 三种排序，网格布局）
- 最近队友（同队次数相对进度条 + 胜率 + 常用英雄）
- OP.GG 出装：自动爬取最新版本推荐，装备图标 + 完整符文树可视化 + 一键写入符文页
- ARAM 增益：CommunityDragon 官方倍率，支持加强 / 削弱筛选

**快捷工具**
- 一键创建 5v5 训练房间 / 5v5 自定义 / 大乱斗自定义
- 快速进入匹配队列（单双 420 / 灵活 440 / 匹配 430 / 大乱斗 450 / 斗魂 1700）
- 修改头像 / 移除荣耀水晶框 / 切换在线状态（在线 / 离开 / 移动端 / 请勿打扰）

**体验**
- 夜间模式默认开启，支持浅色 / 深色 / 跟随系统
- 图标走 LCU 本地 HTTPS（~5 ms/张）+ 本地 LRU 缓存，多级导航不卡顿
- 系统托盘图标（关闭按钮最小化不退出）
- 应用内 FluInfoBar 通知（自动动作触发、错误提示）
- 窗口尺寸与位置自动记忆

## 运行

```bash
python -m venv .venv
.venv\Scripts\activate
pip install -r requirements.txt

# 启动 GUI（无参数直接运行）
python app.py

# CLI 调试（不需要 GUI）
python app.py --cli status
python app.py --cli me
python app.py --cli history --count 20
python app.py --cli watch        # 实时订阅 LCU 事件
```

## 目录

```
app/
  common/     # 配置、日志
  lcu/        # LCU 连接、HTTP、WebSocket、API 封装
  core/       # 业务逻辑（战绩分析、选人辅助、自动动作）
  services/   # 外部数据（OP.GG 等）
  cli/        # 命令行调试入口
  view/       # QML UI + Python 桥接
```
