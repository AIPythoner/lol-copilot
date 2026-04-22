# lol-copilot

英雄联盟战绩助手（面向腾讯区），参考 Seraphine / frank / champ-r / rank-analysis。

- UI：PySide6 + [FluentUI-QML](https://github.com/zhuzichu520/PySide6-FluentUI-QML)
- 连接：LCU（League Client Update）本地 HTTPS + WebSocket
- 数据源（推荐/出装）：OP.GG

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
