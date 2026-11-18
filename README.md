# Redmine Project Workspace

Redmine 7.0.2 的「项目工作台」插件：按一个**项目自定义字段**对可见项目分组，左侧树形浏览、右侧显示所选项目的**全部未关闭任务**，并复用 Redmine 原生任务右键菜单（含登记工时）、原生新建任务与原生工时校验逻辑。

- 目标环境：**Redmine 7.0.2.stable**（Rails 8.1.4 / Ruby 4.0.9 / PostgreSQL 16 实测）
- 插件标识：`redmine_project_workspace`
- 不修改 Redmine 核心源码；**无数据库迁移**；不改变任务、工时数据结构。

## 功能

| 功能 | 实现方式 |
|---|---|
| 顶部菜单「项目工作台」 | `init.rb` 注册 `top_menu` 菜单，入口 `/project_workspace` |
| 项目分类树 | 按配置的 `ProjectCustomField` 选项顺序分组；空值/未知值/不可见值进入「未分类」；组可折叠、可搜索、选中状态本地记忆 |
| 右侧任务列表 | 基于 `IssueQuery` + `Issue.visible`：单项目、不含子项目、仅未关闭（`IssueStatus#is_closed`）、分页 25/50/100、默认「更新时间降序 + ID 降序」 |
| 任务筛选 | 全部未关闭 / 仅进行中（非 tracker 默认状态）/ 指派给我 |
| 右键菜单 | **Redmine 7 原生上下文菜单**：`/issues/context_menu` + `context_menu.js`，权限、批量操作、登记工时全部由核心判定 |
| 登记工时 | 菜单项 `登记工时` 指向原生 `/issues/:id/time_entries/new`，提交走原生 `TimelogController#create`，无自建写接口 |
| 新建任务 | 原生 `/projects/:project_id/issues/new`；无 `add_issues` 权限时隐藏按钮 |
| 权限 | 项目树仅含 `Project.visible(user).active.allowed_to(user, :view_issues)`；任务查询走 `Issue.visible`；不新增 `view_workspace` 权限，不做“仅成员可见”的额外限制 |
| 中文界面 | 自带 zh/en 语言包，默认主题下验证 |

## 目录结构

```text
redmine_project_workspace/
  init.rb
  config/routes.rb
  config/locales/{zh,en}.yml
  app/controllers/project_workspace_controller.rb
  app/services/project_workspace/{config,project_groups,issues_finder}.rb
  app/helpers/project_workspace_helper.rb
  app/views/project_workspace/{index,_project_tree,_issues_panel}.html.erb
  app/views/settings/_project_workspace.html.erb
  assets/{stylesheets,javascripts}/project_workspace.*
  script/            # 开发环境测试数据与自动化验证脚本
  docs/              # 安装、兼容性、验收、回滚、截图
```

> Redmine 7 使用 Propshaft，插件静态资源放在插件根的 `assets/` 目录（不是 `app/assets`），访问路径为
> `/assets/plugin_assets/redmine_project_workspace/project_workspace-<digest>.css|js`。

## 安装

1. 将本目录放入 Redmine 的 `plugins/redmine_project_workspace`（Docker 部署可用 bind mount，见 `docs/INSTALL.md`）。
2. 重启 Redmine（本机 Docker：`docker compose restart redmine`）。
3. 以管理员进入「管理 → 插件 → Redmine Project Workspace → 配置」。
4. 在「项目分类字段」下拉框选择一个**已存在的项目自定义字段**（建议：类型“项目”、格式“列表”、单值），保存。
5. 打开顶部「项目工作台」。

无需执行 `rake redmine:plugins:migrate`（本插件没有迁移）。如果部署方式需要预编译资源，按 Redmine 常规方式重启/预编译即可。

详细步骤、字段不可用时的报错说明见 [docs/INSTALL.md](docs/INSTALL.md)。

## 配置与分组规则

- 字段按 **ID** 保存（`Setting.plugin_redmine_project_workspace['project_custom_field_id']`），不使用字段名称模糊匹配。
- 字段必须是 `ProjectCustomField`、`field_format == 'list'`、`multiple == false`；否则工作台显示配置错误提示（管理员可见「配置」链接），不会崩溃。
- 分组顺序 = 字段选项顺序；「未分类」固定最后。
- 以下情况进入「未分类」：空值；不在字段选项中的值；当前用户对该项目**无权查看该字段值**（角色受限时）；多值字段的多个值（配置层面已拒绝多值字段，此处为防御）。
- 仅列 `status = 1`（活跃）项目，归档/关闭项目不显示；直接访问归档项目 URL 返回 403。
- 子项目作为独立项目出现在树中；但**右侧任务永远只显示当前项目自身任务，不含子项目任务**。

## URL 与权限

| 方法 | 路径 | 说明 |
|---|---|---|
| GET | `/project_workspace` | 完整工作台（可带 `project_id`、`page`、`scope`、`sort`、`per_page`） |
| GET | `/project_workspace/issues` | 任务面板；`X-Requested-With: XMLHttpRequest` 返回局部 HTML，否则返回完整页面（无 JS 回退） |
| GET | `/settings/plugin/redmine_project_workspace` | 管理员配置（Redmine 内置插件设置路由） |

- 没有新增写接口；新建任务、登记工时、批量操作全部由 Redmine 原生控制器处理并鉴权。
- 不新增权限项。可见性 = 用户可见项目 + `view_issues`；`add_issues` 决定「新建任务」按钮；`log_time` 由原生右键菜单与 `TimelogController` 判定。
- 匿名用户在开启“需要登录”时由 Redmine 统一拦截；关闭登录限制时只能看到公开项目。

## 测试

- 服务级（35 项）：`script/verify_p0.rb`，依赖 `script/seed_test_data.rb` 与 `script/seed_pagination_project.rb`。
- 浏览器 E2E（31 项，Playwright + 本机 Chrome）：`script/e2e_browser.py`，覆盖登录、分组、切换、右键菜单、登记工时、新建任务、折叠/搜索/记忆、快速切换、权限隔离。
- 结果与证据见 [docs/ACCEPTANCE.md](docs/ACCEPTANCE.md)，截图在 `docs/screenshots/`。

容器内运行服务级验证：

```bash
docker exec -e RAILS_ENV=production -e SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE" redmine \
  bash -c "cd /usr/src/redmine && bundle exec rails runner plugins/redmine_project_workspace/script/verify_p0.rb"
```

## 已知限制

- 右键「登记工时」打开的是 **Redmine 原生工时表单页**，不是工作台内弹窗（符合规格书的“受控复用”要求）。
- 任务表默认列不含估计工时/自定义字段；已登记工时列在用户有 `view_time_entries` 权限时显示。
- 未在 100+ 项目 / 单项目 1000+ 任务规模做正式性能压测（P1）。
- 项目树包含子项目节点；规格书只要求任务不混合子项目，如需隐藏子项目节点可在 v2 增加开关。

## 卸载 / 回滚

见 [docs/ROLLBACK.md](docs/ROLLBACK.md)。删除插件目录并重启即可；无迁移、无表结构变更，任务/工时数据不受影响。

## 许可证

GNU GPL v2（与 Redmine 一致），见 [LICENSE](LICENSE)。
