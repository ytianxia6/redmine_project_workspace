# 阶段 A：环境侦查与兼容性说明

调查对象：`redmine:7.0.2` 官方镜像（Redmine 7.0.2.stable，Rails 8.1.4，Ruby 4.0.9，PostgreSQL 16）。
所有结论来自容器内真实源码（`/usr/src/redmine`），未修改核心文件。

## 1. 版本与运行形态

| 项 | 值 |
|---|---|
| `Redmine::VERSION` | `7.0.2.stable`（`lib/redmine/version.rb`，BRANCH=stable） |
| Rails | 8.1.4 |
| Ruby | 4.0.9 |
| 数据库 | PostgreSQL 16（Docker 命名卷） |
| 部署 | Docker Compose，`127.0.0.1:3002 -> 3000` |
| 已安装插件 | 仅 `redmine_project_workspace`（本插件） |
| 主题 | 默认主题 |

## 2. 项目自定义字段

- 环境实测字段：`项目类型`（ID=1，`field_format=list`，`multiple=false`，`visible=true`）。
- 值通过 `Project#custom_field_value(field)` 读取；可见性判断使用
  `ProjectCustomField#visible_by?(project, user)`：
  - `CustomField#visible_by?` = `visible? || user.admin?`；
  - `ProjectCustomField#visible_by?` 追加 `roles.intersect?(user.roles_for_project(project))`（角色受限时）。
- 结论：必须使用 `visible_by?`，不可见时按「未分类」处理，避免泄漏字段值。

## 3. 项目可见性

- `Project.visible(user)` → `Project.visible_condition(user)`
  → `Project.allowed_to_condition(user, :view_project)`（`app/models/project.rb:178`）。
- 注意：`Project.visible` **包含已归档项目**（实测 admin 可见 `archived-g`）。必须再叠加：
  - `.active`（`status = 1`）排除归档/关闭；
  - `.allowed_to(user, :view_issues)`：`allowed_to_condition` 会附加
    `EXISTS (... enabled_modules em.name='issue_tracking')` 与角色权限条件（`project.rb:189-207`）。
- 本项目实现：`Project.visible(user).active.allowed_to(user, :view_issues).preload(:custom_values)`。

## 4. 任务查询与 open 语义

- `Issue.visible(user)`：`Issue.visible_condition` 基于角色 `issues_visibility`
  （all/default/own/0）与 tracker 粒度权限（`app/models/issue.rb:137-169`）。
- `IssueStatus#is_closed` 是唯一可靠的关闭判定；实测自定义关闭状态「验收完成」被正确排除。
- `IssueQuery`（`app/models/issue_query.rb`）：
  - `IssueQuery.new(project: p, name: ...)` 可设置项目作用域；
  - `add_filter('status_id', 'o', [''])` → 未关闭；
  - `add_filter('subproject_id', '!*', [''])` → **仅主项目**，排除子项目
    （`Query#project_statement`，`app/models/query.rb:963-995`）；
  - `issues(offset:, limit:)` 会按列名预加载关联（`issue_query.rb:413-451`），并处理
    `spent_hours` 的可见汇总；
  - `issue_count` 与 `issues` 使用同一 `base_scope`，计数与列表一致。
- 结论：完全可以使用 IssueQuery 实现工作台列表，无需自写 SQL；排序通过
  `query.sort_criteria=`（`Redmine::SortCriteria` + `sortable_columns` 白名单）。

## 5. 任务右键菜单（关键技术风险）

Redmine 7 已把上下文菜单从 `IssuesController` 拆分：

| 组件 | 实际路径/签名 |
|---|---|
| 路由 | `/issues/context_menu` → `context_menus/issues#index`（`config/routes.rb:61`，GET/POST） |
| 控制器 | `ContextMenus::IssuesController < ContextMenus::BaseController`（`app/controllers/context_menus/issues_controller.rb`） |
| 菜单模板 | `app/views/context_menus/issues.html.erb` |
| 前端 | `app/assets/javascripts/context_menu.js`（document 级 `contextmenu` 监听 + `.js-contextmenu` 点击） |
| 列表 partial | `app/views/issues/_list.html.erb`：`form_tag(data: {cm_url: issues_context_menu_path})`、`tr.hascontextmenu`、`ids[]`、`link_to_context_menu` |
| 引入方式 | `<%= context_menu %>` helper（`app/helpers/application_helper.rb:1686`）注入 `context_menu.js` + CSS 到 `:header_tags` |

菜单加载协议（`context_menu.js:98-166`）：

1. 右键命中 `.hascontextmenu` 行 → 选中该行（勾选其 checkbox）；
2. 取事件目标最近的 `form` 的 `data-cm-url`，`serialize()` 整个表单（含 `ids[]`、`back_url`、CSRF）；
3. `$.ajax(GET url + serialized)` → 服务端返回 `<ul>…</ul>` 菜单 HTML；
4. 菜单项由服务端按权限渲染。

服务端鉴权：`ApplicationController#find_issues`（`app/controllers/application_controller.rb:424`）
使用 `Issue.find_with_preloads(params[:id] || params[:ids])`，并 `raise Unauthorized unless @issues.all?(&:visible?)`，
不可见任务 → 403。

登记工时菜单项：仅当 `@can[:log_time] = @issue&.time_loggable?` 时渲染
（`issue.rb:206`：`allowed_to?(:log_time) && (Setting.timelog_accept_closed_issues? || !closed?)`），
链接为 `new_issue_time_entry_path(@issue)`（`context_menus/issues.html.erb:160-163`）。

**结论：可以完整复用原生右键菜单。** 工作台只需输出与原生列表一致的 DOM 协议
（`form[data-cm-url]` + `tr.hascontextmenu` + `ids[]` + `back_url` + `link_to_context_menu`），
并调用一次 `<%= context_menu %>`。不需要自写伪菜单，也不需要受控降级方案。

## 6. 登记工时链路

- 路由：`resources :issues { resources :time_entries, controller: 'timelog', only: [:new, :create] }`
  → `GET /issues/:issue_id/time_entries/new`（`timelog#new`）、`POST /issues/:issue_id/time_entries`；
  全局表单提交到 `POST /time_entries`（`timelog#create`）。
- 权限：`lib/redmine/preparation.rb:92`：`map.permission :log_time, {:timelog => [:new, :create]}, :require => :loggedin`；
  `TimelogController#create` 另有 `allowed_to?(:log_time, project)` 与 `render_403`
  （`app/controllers/timelog_controller.rb:111-113`）。
- 结论：工作台不新增工时接口，只提供原生链接；提交后 TimeEntry 由核心校验与保存。

## 7. 新建任务链路

- `GET /projects/:project_id/issues/new`（`IssuesController#new`），`add_issues` 在 `create` 中强制检查
  （`issues_controller.rb:152-154`）；无权限时 GET 表单页同样 403（实测只读用户）。
- 结论：工作台仅在有 `add_issues` 且项目启用 `issue_tracking` 时显示按钮，提交完全交给原生控制器。

## 8. 插件机制（Redmine 7）

| 项 | 结论 |
|---|---|
| 插件加载 | `plugins/<id>/init.rb`，`Redmine::Plugin.register` |
| 路由 | 插件 `config/routes.rb` 自动加载（`config/routes.rb:433`） |
| 菜单 | `menu :top_menu, ...`，支持 `:if`/`:after` |
| 设置 | `settings partial:` + 路由 `/settings/plugin/:id`（`SettingsController#plugin`，仅管理员） |
| 静态资源 | 插件根 `assets/`，逻辑路径 `plugin_assets/<id>/...`；实测输出 `/assets/plugin_assets/redmine_project_workspace/project_workspace-<digest>.js` |
| 自动加载 | `app/*` 目录自动加入 Rails autoload paths（`lib/redmine/plugin_loader.rb`） |
| 迁移 | 本插件无 `db/migrate` |

## 9. 风险与决策

| 风险 | 处理 |
|---|---|
| 原生列表 partial 依赖 `@query`、分组、列 helper，直接复用会与局部更新耦合 | 自绘表格但**严格复用原生 DOM 协议**（form/tr/checkbox/context menu），数据仍由 IssueQuery 产出 |
| 核心 context menu 使用 document 级监听 | 工作台局部刷新后新 DOM 自动可用（事件委托），无需重新绑定 |
| 归档项目被 `Project.visible` 返回 | 显式 `.active` + controller 对归档项目返回 403 |
| 字段值可能角色不可见 | `visible_by?` 判定，不可见归「未分类」 |
| 多值字段 | 配置层拒绝 + 运行时防御（多个值不取第一项） |
| 旧响应覆盖新结果 | 前端 AbortController + 递增序号，只应用最新响应 |
