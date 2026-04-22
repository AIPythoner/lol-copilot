# lol-copilot

英雄联盟战绩助手。

- UI：PySide6 + [FluentUI-QML](https://github.com/zhuzichu520/PySide6-FluentUI-QML)
- 连接：LCU（League Client Update）本地 HTTPS + WebSocket
- 数据源（推荐/出装）：OP.GG

---

## ⚠️ 免责声明

> **请在使用前仔细阅读。**

- **完全基于官方开放接口实现**。本工具所有功能都通过 Riot 官方对外暴露的 **LCU（League Client Update）API** 完成——这是英雄联盟客户端自身用于前后端通信的公开接口，通过本地 HTTPS（`127.0.0.1`）+ 自签证书 + Basic Auth 对外提供，**任何第三方工具（含本项目）都与客户端自带插件使用同一套接口**，不涉及内存读取、封包修改、代码注入等任何外挂行为。
- **完全开源、无后门、无病毒**。源码 100% 公开可审，不含恶意代码、不收集任何用户数据、不上传隐私信息。所有网络访问仅限以下三处：本机 LCU（`127.0.0.1`，本地进程间通信）、Community Dragon 官方 CDN（游戏资源图片）、OP.GG 公开页面（出装推荐）。
- **仅供个人学习交流使用**。本项目出于技术研究与个人使用目的开发，**严禁用于任何商业用途**，包括但不限于：代打代练、付费售卖、捆绑推广、二次打包贩售、付费会员服务等任何盈利行为。
- **使用风险自担**。读取类功能（战绩查询、段位展示、选人信息等）属于 LCU 接口的正常使用场景，风险极低。但"自动接受 / 自动禁用 / 自动选择"等**自动化功能可能违反游戏服务条款（ToS）**，存在账号被封禁的风险。是否启用请自行评估并承担全部后果。
- **与 Riot Games / League of Legends 无关**。本项目为非官方第三方工具，未获 Riot Games, Inc. 授权、认可或背书。项目中引用的所有游戏资源、图片、数据的版权均归 Riot Games, Inc. 所有。
- **不提供任何形式的担保**。作者不对因使用本工具导致的任何账号处罚、数据丢失、客户端异常或其他任何直接 / 间接损失承担任何责任。一经使用即视为已阅读并同意本声明。

---

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

## 打包 / Release

项目使用 GitHub Actions + PyInstaller 生成 Windows one-dir 包。推送 `v*` tag 后会自动构建并发布 Release：

```bash
git tag v0.1.0
git push origin v0.1.0
```

Release 产物是 `lol-agent-windows-<version>.zip`，解压后运行 `lol-agent/lol-agent.exe`。也可以在 GitHub Actions 页面手动触发 `Build Windows Release`，手动构建只上传 artifact，不创建 Release。

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
