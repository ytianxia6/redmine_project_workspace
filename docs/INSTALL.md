# 安装与部署

目标：Redmine **7.0.2.stable**。以下命令以本机开发环境（Docker Compose、Windows + PowerShell）为例，同时给出通用部署要点。

## 1. 前置检查

1. 确认 Redmine 版本：

   ```bash
   bundle exec rake about RAILS_ENV=production
   ```

   版本应为 `Redmine 7.0.2.stable`。
2. 准备一个**项目自定义字段**（管理员操作）：
   - 管理 → 自定义字段 → 项目 → 新建；
   - 名称示例：`项目类型`；
   - 格式：**列表**；
   - 可能的值：`调研`、`开发`、`维护`（按实际业务填写）；
   - **不要勾选“多重取值”**（工作台要求单值）；
   - 可为该字段配置“对哪些角色可见”，工作台会遵守该可见性。
3. 备份：部署到现有环境前，备份 `config/`、`plugins/`、`files/` 与数据库（见 `docs/ROLLBACK.md`）。

## 2. 安装插件

### Docker（本仓库同款环境）

`redmine-workspace-dev/compose.yaml` 已将插件目录 bind mount 到容器：

```yaml
volumes:
  - type: bind
    source: ../redmine_project_workspace
    target: /usr/src/redmine/plugins/redmine_project_workspace
    bind:
      create_host_path: false
```

启动与重启：

```powershell
cd redmine-workspace-dev
docker compose up -d
docker compose restart redmine
docker compose logs --tail 100 redmine
```

### 传统部署

```bash
cp -r redmine_project_workspace /path/to/redmine/plugins/
# 重启应用（Passenger/Puma/unicorn 按现网方式）
```

### 资源说明

- Redmine 7 使用 Propshaft + importmap；插件静态资源位于插件的 `assets/` 目录，自动映射为
  `/assets/plugin_assets/redmine_project_workspace/project_workspace-<digest>.css|js`。
- 不需要 `rake redmine:plugins:migrate`（没有 migration）。
- 若现网使用 `rake assets:precompile` 且启动时不自动检测插件资源，请在重启前执行一次预编译，或确认 `redmine_detect_update` 行为与现网一致。

## 3. 配置分类字段

1. 管理员登录。
2. 打开 **管理 → 插件 → Redmine Project Workspace**（`/settings/plugin/redmine_project_workspace`）。
3. 在「项目分类字段」下拉框选择第 1 步创建的字段，保存。
4. 保存后设置立即生效，并持久化在 `settings` 表（重启后保持）。

### 字段不可用时的表现

| 情况 | 工作台提示 |
|---|---|
| 未配置 | 「项目分类字段尚未配置」+ 管理员可见「配置」链接 |
| 字段被删除 | 「已配置的项目分类字段不存在」 |
| 字段为多值 | 「已配置的项目分类字段是多值字段」，并拒绝渲染分组 |
| 字段格式不是列表 | 配置无效提示 |

## 4. 验证

1. 顶部菜单出现「项目工作台」，进入 `/project_workspace`。
2. 左侧出现按字段选项分组的项目树；首次默认选中第一组第一个项目。
3. 右侧列出该项目未关闭任务；右键任务行出现原生菜单，包含「登记工时」（有 `log_time` 权限时）。
4. 点击「新建任务」进入 `/projects/:identifier/issues/new`。

自动化验证：

```powershell
# 服务级 35 项（需先准备测试数据，见下）
docker exec -e RAILS_ENV=production -e SECRET_KEY_BASE="$env:REDMINE_SECRET_KEY_BASE" `
  redmine-workspace-dev-redmine-1 bash -c `
  "cd /usr/src/redmine && bundle exec rails runner plugins/redmine_project_workspace/script/verify_p0.rb"

# 浏览器 E2E 31 项（本机需安装 Chrome 与 pip install playwright）
python script/e2e_browser.py
```

开发环境测试数据重建：

```bash
docker exec -e RAILS_ENV=production -e SECRET_KEY_BASE="$REDMINE_SECRET_KEY_BASE" <redmine容器> \
  bash -c "cd /usr/src/redmine && bundle exec rails runner plugins/redmine_project_workspace/script/seed_test_data.rb"
```

## 5. 部署到生产前的检查清单

- [ ] 在 Redmine 7.0.2 的副本/测试环境完成安装与 P0 验收。
- [ ] 已备份代码、`config/`、`files/` 与数据库。
- [ ] 确认选择的项目自定义字段为单值列表，且可见性符合预期。
- [ ] 确认现网资源预编译/重启方式，避免静态资源 404。
- [ ] 验证匿名/普通用户/管理员的可见范围与本环境一致。
