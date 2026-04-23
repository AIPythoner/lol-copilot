# QML / PySide 性能优化指引

本文基于一次真实优化经验（战绩详情页 4s → 1s）整理，给本项目及类似 PySide6 + QtQuick/QML 项目做首屏和交互优化时做参考。

---

## 一、案例：战绩详情页打开耗时 4 秒

### 现象

点击战绩列表里的一场对局，`MatchDetailPage` 从触发到"完全出现"要 3–4 秒。骨架屏先亮 1s+、之后内容再慢慢成型。冷启动和缓存命中表现都差。

### 根因拆解

按发生顺序看耗时：

| 阶段 | 典型耗时 | 成因 |
|---|---|---|
| ① Python 侧 LCU 请求 + 投影 | 300–1500ms | `/lol-match-history/.../games/{id}` 走 localhost HTTPS |
| ② `matchDetailChanged` 到达 → QML 同步构建 `MatchDetailContent` | 200–500ms | 200+ Item、150+ Image 在 GUI 线程一次性 new |
| ③ **Tooltip binding 访问大 dict property** | **1500–3000ms** | **真正的元凶**，详见下文 |
| ④ 图片 provider 异步拉 100+ 张图标 | 200–500ms | 可并行，但首次会堆积 |
| ⑤ 入场动画 + DamageBar 宽度过渡 | 300ms+ | 视觉伪加载感 |

### 元凶：`@Property("QVariant")` 返回大 dict 的隐性代价

PySide 把 Python dict 作为 `@Property("QVariant")` 暴露给 QML 时，**每次 QML 读取该 property，都会把整个 dict 递归深拷贝**成 QVariantMap/JSValue。

```python
@Property("QVariant", notify=gameDataChanged)
def itemsById(self) -> dict:
    return self._items_by_id   # 1000+ 条，每条本身又是 dict
```

QML 侧这样用：

```qml
// ItemSlot.qml 旧代码
FluTooltip {
    text: Lcu.itemsById[String(root.itemId)]
        ? Lcu.itemsById[String(root.itemId)].name
        : ""
    visible: showTooltip && mouse.containsMouse && text.length > 0
}
```

一页里 70 个 ItemSlot × 2 次访问 = **140 次千级 dict 深拷贝**；加上 champions、spells 再叠加 60 次。单次 marshal 约 10–30ms，合计 1.5–3s。**这部分开销完全发生在 Python↔QML 边界，和真正的渲染无关**。

此外，QML binding 会**持有**求值过程中用到的 JSValue 以便依赖失效时重算——上百份"整个 items dict 的副本"同时挂在 QML JS heap 上，会让页面打开时内存飙升上百 MB。

### 五项改动（由效果小到大）

| 项 | 做法 | 量级 |
|---|---|---|
| A | `openMatchDetail` 命中缓存时同步写 `_match_detail`，跳过 180ms 最小 skeleton 与 loading 帧 | -180ms（命中时） |
| B | `MatchDetailPage` 的 `contentLoader` 加 `asynchronous: true`，并在渲染期保持骨架防止空白闪烁 | 主线程不再冻屏 |
| C | `ParticipantRow` 里 augments / runes 两分支合并为单 `Loader`，按 `detail.usesAugments` 二选一实例化 | 每行省 6 个 Item |
| D | 删 `DamageBar` 的 `Behavior on width` | -300ms 视觉 |
| **E** | Tooltip 走 `Lcu.itemName(id)` / `championName` / `spellName` slot（只回传字符串），且 hover 时才求值 | **-1500~3000ms**，内存省百 MB 级 |

最终冷启动稳定在 800–1200ms 区间，缓存命中近似瞬开。

---

## 二、通用原则

### 1. 不要把大 dict / list 作为 `@Property("QVariant")` 让 binding 直接取

**症状**：binding 里写 `Lcu.someDict[key].prop`。
**风险**：每次 binding 求值都会整表深拷贝；多点访问各自持有副本，heap 无法回收。

**替代**：

- 用 `@Slot(int, result=str)` / `@Slot(str, result="QVariant")` 类的细粒度查询函数，出入参都是小标量。
  ```python
  @Slot(int, result=str)
  def itemName(self, iid: int) -> str:
      entry = self._items_by_id.get(str(iid))
      return entry.get("name", "") if entry else ""
  ```
- 如果必须暴露集合，考虑：
  - 只暴露"当前页数据"这种小切片，而不是全库字典。
  - 用 `QAbstractListModel` 让 QML 按行访问，避免整张表拷贝。

### 2. Tooltip / 低频触发的 text 要懒求值

Tooltip/Popup 这种"hover 才可见"的组件，text binding 默认是**始终激活**的——UI 不显示不代表 binding 不求值。

```qml
// bad: 首帧就会 marshal
text: Lcu.itemName(root.itemId)

// good: hover 时才求值
text: mouse.containsMouse && root.itemId > 0
    ? Lcu.itemName(root.itemId)
    : ""
```

### 3. 大 QML 子树用 `Loader { asynchronous: true }`

对"数据到了才要构建"的重页面（比如详情页内容），外层套一个 `Loader`，打开 `asynchronous: true`，Qt 会把 QML 对象实例化分摊到后台线程，GUI 线程保持响应。

注意配套：
- 用 `status === Loader.Ready` 做可见性切换。
- 异步期间保持骨架屏，避免短暂空白。
- `implicitHeight` 依赖 `item.implicitHeight`，在 `null` 时退化为 0 要想好布局影响。

### 4. 互斥分支不要"都建出来只改 visible"

`visible: false` **不会**阻止 QML 实例化子树。两套只会二选一的界面，并列放两份是纯浪费。改成 `Loader { sourceComponent: cond ? a : b }` + 两个 `Component`，只实例化用到的一份。

### 5. 小心装饰性动画的"伪加载感"

`Behavior on width`、`Behavior on opacity`、`NumberAnimation` 这类过渡动画即便每个只有 200–300ms，10 份堆在首帧会让用户误以为"还在加载"。首屏渲染路径上要么删，要么用 `enabled: false` gate 住仅在交互变更时生效。

### 6. 同步置数据避免无意义的 loading → data 闪烁

后端缓存命中的场景，不要"先发 loading → 异步发 data"，直接同步把数据塞进 property 再 emit，QML 会一次性拿到稳定状态，不会出现骨架屏一闪的"抖动感"。

```python
# bad
self._set_match_detail_loading(gid)
self._spawn(self._publish_match_detail(cached))

# good (cache hit)
self._match_detail = cached
self.matchDetailChanged.emit()
```

---

## 三、如何定位类似问题

优先怀疑的地方（按经验排名）：

1. **binding 里访问 PySide 大 QVariant property**——用 Grep 搜 `Lcu.\w+By\w*\[` 或 `Lcu\.\w+\.length` 之类模式。
2. **Repeater 的 model 是 JS filter/find/slice 返回值，且外层 property 每次 detail 变化都重建**——filter/find 会在 model 引用变化时整体重跑，delegate 全量重建。必要时用 `readonly property` 缓存、或在 Python 侧先算好。
3. **大量 Image 的 `source` 来自 custom provider，而 provider 里是同步 HTTPS**——检查 `QQuickImageProvider.requestPixmap` 的 worker 数量、cache 命中率、preload 是否命中。
4. **有没有 orphan 页面在后台持续响应 Lcu signal**——参考 `AppNavigationView.qml` 里对 `StackView.pop` 的 destroy 补丁。若当前页打开慢但偶发，可能是前一个页面在 `matchDetailChanged` 里还在重建 100+ Image。

### 最小化打点方案

```python
import time
t0 = time.monotonic()
# ...
log.info("match detail fetch=%dms", int((time.monotonic() - t0) * 1000))
```

QML 侧：

```qml
Loader {
    onStatusChanged: if (status === Loader.Ready)
        console.log("loader ready", Date.now() - page.__t0)
}
Component.onCompleted: page.__t0 = Date.now()
```

把 click → bridge slot → publish → loader ready 分别打点，一眼能看出耗时在哪一段。

---

## 四、快速检查清单

提交新 QML 页面前自检：

- [ ] Tooltip、Popup 这类 text binding 是否 hover/open 时才求值？
- [ ] 有没有直接访问 `Lcu.xxxById[...]` 的 binding？改走 `@Slot` 函数。
- [ ] 数据量大的 Repeater，model 是否每次外层 property 变化都重建？
- [ ] 入场动画（`Behavior on *`）是否会在首帧触发？
- [ ] 页面入口的 Python 异步 publish 有没有不必要的 min-skeleton 最小延时？
- [ ] 互斥分支是否在用 `visible` 掩盖而不是 `Loader` 二选一？

---

本文随项目持续优化更新。下一步可能的方向：持久化 `_match_detail_cache` 到磁盘（冷启动秒开）、`LcuImageProvider` 预热策略随滚动可视范围走、`QAbstractListModel` 替代纯 JS 数组的 Repeater model。
