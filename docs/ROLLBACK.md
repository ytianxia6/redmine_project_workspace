# 卸载与回滚

本插件**没有数据库迁移**，不新增/修改表结构，不改变任务与工时数据。卸载只需移除插件目录并重启。

## 1. 回滚前

1. 备份当前插件目录（或直接使用 Git 回滚）：

   ```bash
   cp -r plugins/redmine_project_workspace /backup/redmine_project_workspace-$(date +%F)
   ```

2. 记录当前分类字段 ID（可选，便于重新安装）：

   ```bash
   bundle exec rails runner "puts Setting.plugin_redmine_project_workspace.inspect" RAILS_ENV=production
   ```

## 2. 卸载步骤

### Docker（本仓库环境）

1. 从 `redmine-workspace-dev/compose.yaml` 移除 `redmine_project_workspace` 的 bind mount，或直接删除宿主机插件目录：
   ```powershell
   Remove-Item -Recurse -Force ..\redmine_project_workspace
   ```
2. 重启：
   ```powershell
   docker compose restart redmine
   ```
3. （可选）清理已生成的静态资源：
   ```bash
   docker exec <redmine容器> bash -lc "rm -f /usr/src/redmine/public/assets/plugin_assets/redmine_project_workspace-*; rm -rf /usr/src/redmine/tmp/cache"
   ```

### 传统部署

```bash
rm -rf /path/to/redmine/plugins/redmine_project_workspace
rm -rf /path/to/redmine/tmp/cache
# 按现网方式重启应用
```

## 3. 清理配置（可选）

插件设置保存在 `settings` 表中（`plugin_redmine_project_workspace`），删除插件后该行不会影响 Redmine，
可保留以便重装时复用；如需彻底清理：

```bash
bundle exec rails runner "Setting.plugin_redmine_project_workspace = {}" RAILS_ENV=production
```

## 4. 回滚后验证

1. `GET /project_workspace` 返回 404；
2. 顶部菜单不再出现「项目工作台」；
3. `/projects`、`/issues`、`/time_entries` 正常；
4. 任务、工时数量与卸载前一致（无数据变更）。

## 5. 数据说明

- 无 migration，无新表/新列；TimeEntry、Issue 记录均为原生写入，卸载后保持可用。
- 若同时回滚测试数据，开发环境可执行 `docker compose down -v` 重建（仅限隔离开发环境，会删除开发库数据，禁止用于生产）。
