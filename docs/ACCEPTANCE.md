# 验收报告（P0）

测试环境：Redmine 7.0.2.stable（Docker `redmine:7.0.2`，Rails 8.1.4，Ruby 4.0.9，PostgreSQL 16），
默认主题，中文界面，`127.0.0.1:3002`。

测试数据：`script/seed_test_data.rb` + `script/seed_pagination_project.rb`（9 个项目、4 个分类值/未分类、
6 个测试账号、私有任务、子项目、自定义关闭状态、30 条分页任务）。

## 自动化测试结果

| 套件 | 结果 | 说明 |
|---|---|---|
| 服务级 `script/verify_p0.rb` | **35 / 35 PASS** | 配置、分组、可见性、open 语义、子项目排除、私有任务、排序白名单、分页、仅进行中、工时权限、字段角色可见性、多值字段拒绝 |
| 浏览器 E2E `script/e2e_browser.py` | **31 / 31 PASS** | 登录、分组、折叠/搜索/记忆、项目切换、右键菜单、登记工时、新建任务、连续右键、快速切换、权限隔离 |
| 回归（原生页面） | PASS | `/projects`、`/issues`、`/time_entries`、`/projects/dev-c`、`/projects/dev-c/issues` 均 200 |
| 权限/越权 HTTP 检查 | PASS | 见下表 P0-8/P0-9 证据 |

运行方式与输出摘要：

```text
$ bundle exec rails runner plugins/redmine_project_workspace/script/verify_p0.rb
...
35/35 checks passed

$ python script/e2e_browser.py
...
31/31 checks passed
```

## P0 逐项结论

### P0-1 插件加载、顶部菜单、不修改核心

- **PASS**
- 容器启动无插件加载错误；顶部菜单出现「项目工作台」并高亮。
- 插件目录独立，核心文件零改动（未修改 `/usr/src/redmine/app|lib|config`，未打补丁）。
- 证据：`docs/screenshots/01-workspace-admin.png`，页面 HTML 中 `controller-project_workspace action-index`。

### P0-2 管理员选择项目自定义字段，配置持久化

- **PASS**
- 设置页 `GET /settings/plugin/redmine_project_workspace` 200，下拉框列出 `项目类型 (#1, list)`。
- `POST` 保存后 302；重启容器后设置页仍显示 `selected value="1"`，工作台分组正常。
- 字段删除/多值/格式不符时工作台显示友好错误（已验证：非法 ID → 「已配置的项目分类字段不存在」；多值 → 「多值字段」提示，且不渲染分组）。

### P0-3 分类分组、折叠、未分类

- **PASS**
- 分组顺序实测 `调研` → `开发` → `维护` → `未分类`，计数分别为 2/4/2/1（管理员视角，含分页测试项目）。
- 「未分类」包含未设置字段值的 `未分类项目F`；分组标题可折叠并在刷新后保持（E2E）。
- 证据：截图 01；服务级分组断言 5 项。

### P0-4 右侧列出项目全部未关闭、当前用户可见任务（含他人任务，排除子项目/其他项目）

- **PASS**
- 数量与 `Issue.visible.open.where(project_id: dev-c)` 完全一致；包含他人负责的任务（report1 的任务）。
- 不含子项目任务（`子项目任务：不应出现在开发项目C`），不含其他项目任务。
- 证据：`verify_p0.rb` 任务断言；E2E `panel count matches rows`。

### P0-5 关闭任务不显示，状态名称不影响判定

- **PASS**
- 已关闭/已拒绝任务不出现；自定义关闭状态「验收完成」任务同样被排除（按 `IssueStatus#is_closed` 判定）。
- 证据：`verify_p0.rb`「不包含已关闭任务」「包含全部开放任务（不含关闭状态）」；E2E「closed issue not listed」。

### P0-6 右键登记工时 → 原生登记界面 → 有效 TimeEntry

- **PASS**
- 右键任务行弹出 **Redmine 原生上下文菜单**，含「登记工时」；点击进入
  `/issues/:id/time_entries/new`（原生表单），提交后生成 TimeEntry。
- dev1（普通成员，有 `log_time`）通过浏览器完成 0.75h 登记；数据库：
  `time_entries(issue_id=7, user=dev1, hours=0.75, comments='E2E dev1 工时')`，原生
  `/time_entries?issue_id=7` 可查到。
- 证据：`docs/screenshots/02-context-menu.png`、`03-time-entry-form.png`。

### P0-7 新建任务 → 原生创建页 → 工作台可见

- **PASS**
- 工作台「新建任务」进入 `/projects/dev-c/issues/new`（项目已预选），提交成功后在右侧列表出现。
- 证据：E2E「new issue form preselects project」「issue created」「new issue visible in workspace」；
  dev1 视角同样通过。

### P0-8 权限隔离与手工 URL 越权

- **PASS**

| 场景 | 结果 |
|---|---|
| viewer1（只读角色，有 `view_issues`，无 `add_issues`/`log_time`） | 工作台无「新建任务」按钮；右键菜单无「登记工时」 |
| viewer1 直接访问 `/issues/4/time_entries/new` | **403** |
| viewer1 直接 `POST /time_entries` | **403** |
| viewer1 直接 `POST /projects/dev-c/issues` | **403** |
| outsider（非成员）访问私有项目 `?project_id=3` | 302 → 登录页（原生登录策略） |
| outsider 访问 `/project_workspace/issues?project_id=3` | 302 → 登录页 |
| outsider 构造 `/issues/context_menu?ids[]=4`（私有任务） | 302 → 登录页 |
| 归档项目 `?project_id=8`（含管理员） | **403** |
| 项目 ID 不存在 | 404 |

- 左侧树对 outsider 只显示公开项目，不泄漏私有项目名称/数量。

### P0-9 隐藏字段值、私有任务不泄漏；撤权后异步请求不泄漏

- **PASS**
- 私有任务「私有缺陷修复」：dev1（被指派）可见，viewer1 不可见；`Issue.visible` 语义一致。
- 字段角色可见性：临时将字段设为「仅开发人员可见」后，viewer1 的分组只剩「未分类」，无任何分类值泄漏；管理员仍看到全部分组（测试后已恢复）。
- **实时撤权**：dev1 打开工作台后被移除 dev-c 成员关系 → 工作台刷新后树中无 dev-c，`/project_workspace/issues?project_id=3` 返回 **403**，原生工时页也返回 **403**（测试后已恢复成员关系）。

### P0-10 中文界面、默认主题布局、0 任务/0 项目空态

- **PASS**
- 中文菜单/表头/筛选/空态；默认主题下左右 25%/75% 布局正常（截图 01）。
- 0 任务：`调研项目B` 显示「没有未关闭的任务」。
- 0 项目：临时将全部项目设为私有后，非成员用户显示「没有可访问的项目」，不渲染空树（数据已恢复）。
- 证据：`docs/screenshots/01-workspace-admin.png`、`04-viewer1.png`。

## P1 建议项

| 编号 | 结果 | 说明 |
|---|---|---|
| 11 分页/排序/筛选/快速切换 | PASS | 25/50/100、`sort` 白名单、`scope` 筛选、快速切换只应用最后一个响应（E2E） |
| 12 同页 5 次连续右键 | PASS | 5 次右键均指向正确 issue，无旧 DOM/旧 ID（E2E） |
| 13 归档隐藏、字段变更后分组更新 | 部分 | 归档隐藏与 403 已验证；字段值变更后分组更新依赖页面刷新（未单独自动化） |
| 14 100+ 项目/1000+ 任务性能 | 未测试 | 本环境数据量小；单次请求 < 2s 未做正式压测 |
| 15 无 JS 回退 | PASS | 列表与分页均为服务端渲染普通链接；`/project_workspace/issues?...` 无 XHR 时返回完整页面 |

## 已知限制与未完成项

1. 右键「登记工时」打开原生页面，不提供工作台内弹窗（符合规格书受控复用要求，未声称弹窗内完成）。
2. 子项目作为独立项目节点出现在左侧树；右侧任务严格不含子项目任务。
3. 未做大规模性能压测（P1-14）。
4. 字段值变更后的分组刷新依赖刷新页面（P1-13 未完全自动化）。
5. 测试截图与数据来自开发容器，生产部署前需在副本环境重新执行验收。
