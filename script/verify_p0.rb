# frozen_string_literal: true

# P0 数据级自动化验证（依赖 script/seed_test_data.rb 创建的数据）。
# 用法（容器内）：
#   RAILS_ENV=production bundle exec rails runner plugins/redmine_project_workspace/script/verify_p0.rb
# 退出码 0 表示全部通过。

$failures = []
$checks = 0

def assert(label, condition, detail = nil)
  $checks += 1
  if condition
    puts "PASS  #{label}"
  else
    $failures << label
    puts "FAIL  #{label}#{detail ? " (#{detail})" : ''}"
  end
end

def as(user)
  User.current = user
  yield
ensure
  User.current = nil
end

def finder(project_identifier, user, params = {})
  project = Project.find_by(:identifier => project_identifier)
  raise "missing project #{project_identifier}" if project.nil?

  ProjectWorkspace::IssuesFinder.new(:project => project, :user => user, :params => params).call
end

def groups(user)
  field = ProjectWorkspace::Config.usable_field
  ProjectWorkspace::ProjectGroups.new(:user => user, :field => field).call
end

admin = User.find_by(:login => 'admin')
dev1 = User.find_by(:login => 'dev1')
viewer1 = User.find_by(:login => 'viewer1')
outsider = User.find_by(:login => 'outsider')

# --- 配置 ---
field = ProjectWorkspace::Config.custom_field
assert('配置：项目分类字段存在', field.present?, field&.name)
raise 'custom field missing' if field.nil?

assert('配置：字段为项目自定义字段', field.is_a?(ProjectCustomField))
assert('配置：字段格式为 list', field.field_format == 'list', field.field_format)
assert('配置：字段为单值', field.multiple == false)
assert('配置：配置无错误', ProjectWorkspace::Config.problem.nil?, ProjectWorkspace::Config.problem)

# --- 项目分组 ---
admin_groups = groups(admin)
assert('分组：管理员有 4 个分组', admin_groups.groups.size == 4, admin_groups.groups.map(&:label).inspect)
assert('分组：前三个分组按字段选项顺序',
       admin_groups.groups.first(3).map(&:label) == ['调研', '开发', '维护'],
       admin_groups.groups.map(&:label).inspect)
assert('分组：未分类在最后', admin_groups.groups.last.uncategorized?,
       admin_groups.groups.map(&:label).inspect)
assert('分组：归档项目被隐藏', admin_groups.groups.none? { |g| g.projects.any? { |p| p.identifier == 'archived-g' } })
assert('分组：未分类包含未设置字段的项目',
       admin_groups.groups.find(&:uncategorized?)&.projects&.any? { |p| p.identifier == 'uncategorized-f' })

dev_groups = groups(dev1)
assert('分组：dev1 看不到私有项目H', dev_groups.groups.none? { |g| g.projects.any? { |p| p.identifier == 'private-h' } })
assert('分组：dev1 看得到开发项目C', dev_groups.groups.any? { |g| g.projects.any? { |p| p.identifier == 'dev-c' } })

outsider_groups = groups(outsider)
assert('分组：外部用户看不到私有项目C', outsider_groups.groups.none? { |g| g.projects.any? { |p| p.identifier == 'dev-c' } })
assert('分组：外部用户看得到公开项目A', outsider_groups.groups.any? { |g| g.projects.any? { |p| p.identifier == 'research-a' } })

# --- 任务查询：open 语义、子项目排除、私有任务 ---
dev_c = Project.find_by(:identifier => 'dev-c')
admin_expected = as(admin) { Issue.visible.open.where(:project_id => dev_c.id).count }
admin_ids = as(admin) { Issue.visible.open.where(:project_id => dev_c.id).ids.sort }
admin_result = finder('dev-c', admin)
assert('任务：管理员 dev-c 数量与 Issue.visible.open 一致',
       admin_result.count == admin_expected, "#{admin_result.count} vs #{admin_expected}")
assert('任务：不包含子项目任务',
       admin_result.issues.none? { |i| i.subject.include?('不应出现在开发项目C') })
assert('任务：不包含已关闭任务',
       admin_result.issues.none? { |i| i.status.is_closed? })
assert('任务：包含全部开放任务（不含关闭状态）',
       admin_result.issues.map(&:id).sort == admin_ids)

dev1_result = finder('dev-c', dev1)
assert('任务：dev1 能看到自己被指派的私有任务',
       dev1_result.issues.any? { |i| i.subject.include?('私有缺陷修复') })

viewer_expected = as(viewer1) { Issue.visible.open.where(:project_id => dev_c.id).count }
viewer_result = finder('dev-c', viewer1)
assert('任务：只读用户看不到私有任务',
       viewer_result.issues.none? { |i| i.subject.include?('私有缺陷修复') })
assert('任务：只读用户数量与可见范围一致',
       viewer_result.count == viewer_expected, "#{viewer_result.count} vs #{viewer_expected}")

outsider_result = finder('dev-c', outsider)
assert('任务：外部用户私有项目返回 0 条', outsider_result.count.zero?)

# --- 排序白名单 / 分页 ---
page1 = finder('workspace-pagination', admin, :page => '1')
page2 = finder('workspace-pagination', admin, :page => '2')
wide = finder('workspace-pagination', admin, :per_page => '50')
assert('分页：默认 25 条', page1.issues.size == 25, page1.issues.size.to_s)
assert('分页：第二页 5 条', page2.issues.size == 5, page2.issues.size.to_s)
assert('分页：per_page=50 返回 30 条', wide.issues.size == 30, wide.issues.size.to_s)

sorted = finder('dev-c', admin, :sort => 'subject:asc')
assert('排序：subject:asc 生效', sorted.issues.map(&:subject) == sorted.issues.map(&:subject).sort)

evil = finder('dev-c', admin, :sort => 'id;DROP TABLE issues')
assert('排序：非法排序被忽略并使用默认排序',
       evil.sort == [%w[updated_on desc], %w[id desc]])

# --- 仅进行中 ---
in_progress = finder('dev-c', admin, :scope => 'in_progress')
assert('筛选：仅进行中不含关闭状态', in_progress.issues.none? { |i| i.status.is_closed? })
assert('筛选：仅进行中不含 tracker 默认状态',
       in_progress.issues.none? { |i| Tracker.where(:default_status_id => i.status_id).exists? })

# --- 工时权限判断 ---
issue4 = Issue.find(4)
assert('工时：dev1 可登记 issue#4', issue4.time_loggable?(dev1))
assert('工时：viewer1 不可登记 issue#4', !issue4.time_loggable?(viewer1))

# --- 字段角色可见性：不可见值不得泄漏 ---
field = ProjectCustomField.find_by(:name => '项目类型')
developer_role = Role.find_by(:name => '开发人员')
begin
  field.update!(:visible => false, :role_ids => [developer_role.id])
  restricted = groups(viewer1)
  assert('字段可见性：受限用户只看到未分类',
         restricted.groups.size == 1 && restricted.groups.first.uncategorized?,
         restricted.groups.map(&:label).inspect)
  admin_restricted = groups(admin)
  assert('字段可见性：管理员仍可见分类值', admin_restricted.groups.size == 4,
         admin_restricted.groups.map(&:label).inspect)
ensure
  field.update!(:visible => true, :role_ids => [])
end

# --- 多值字段配置拒绝 ---
begin
  field.update!(:multiple => true)
  assert('配置校验：多值字段被拒绝', ProjectWorkspace::Config.problem == :multiple,
         ProjectWorkspace::Config.problem)
ensure
  field.update!(:multiple => false)
end
assert('配置校验：恢复单值后可用', ProjectWorkspace::Config.problem.nil?)

puts "\n#{$checks - $failures.size}/#{$checks} checks passed"
exit($failures.empty? ? 0 : 1)
