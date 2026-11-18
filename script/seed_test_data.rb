# frozen_string_literal: true

# 开发环境测试数据（幂等）。仅在隔离的 Redmine 7.0.2 开发容器中运行。
# 用法：
#   bundle exec rails runner plugins/redmine_project_workspace/script/seed_test_data.rb RAILS_ENV=production

ADMIN_PASSWORD = '11111111'

def say(msg)
  puts "[seed] #{msg}"
end

def ensure_user(login, firstname, lastname, admin: false)
  user = User.find_by_login(login)
  if user
    say "user exists: #{login}"
  else
    user = User.new(login: login, firstname: firstname, lastname: lastname,
                    mail: "#{login}@example.test", admin: admin,
                    language: 'zh', status: User::STATUS_ACTIVE,
                    password: ADMIN_PASSWORD, password_confirmation: ADMIN_PASSWORD)
    user.must_change_passwd = false
    user.save!
    say "user created: #{login}"
  end
  user.password = ADMIN_PASSWORD
  user.password_confirmation = ADMIN_PASSWORD
  user.must_change_passwd = false
  user.status = User::STATUS_ACTIVE
  user.language = 'zh'
  user.save!
  user
end

# 1. 管理员
admin = ensure_user('admin', 'Redmine', 'Admin', admin: true)
Setting.default_language = 'zh'
Setting.login_required = '0'

# 2. 项目分类自定义字段（单值 list）
cf = ProjectCustomField.find_by(name: '项目类型')
if cf.nil?
  cf = ProjectCustomField.create!(
    name: '项目类型', field_format: 'list', is_for_all: true, multiple: false,
    possible_values: %w[调研 开发 维护], visible: true
  )
  say "custom field created: #{cf.name}##{cf.id}"
else
  cf.possible_values = %w[调研 开发 维护]
  cf.multiple = false
  cf.is_for_all = true
  cf.visible = true
  cf.save!
  say "custom field updated: #{cf.name}##{cf.id}"
end

# 3. 自定义关闭状态（验证按 is_closed 而非名称判定）
closed_status = IssueStatus.find_by(name: '验收完成')
if closed_status.nil?
  closed_status = IssueStatus.create!(name: '验收完成', is_closed: true)
  say "closed status created: #{closed_status.name}##{closed_status.id}"
end

# 4. 只读角色（有 view_issues，无 add_issues / log_time）
readonly_role = Role.find_by(name: '只读观察者')
if readonly_role.nil?
  readonly_role = Role.create!(name: '只读观察者', permissions: %w[view_issues])
  readonly_role.save!
  say "role created: #{readonly_role.name}##{readonly_role.id}"
end

dev_role = Role.find_by(name: '开发人员')
reporter_role = Role.find_by(name: '报告人员')

# 5. 用户
dev1 = ensure_user('dev1', '开发', '一')
dev2 = ensure_user('dev2', '开发', '二')
viewer1 = ensure_user('viewer1', '观察者', '一')
reporter1 = ensure_user('report1', '报告', '一')
outsider = ensure_user('outsider', '外部', '用户')
say "users ready: admin, dev1, dev2, viewer1, report1, outsider"

def ensure_project(identifier, name, attrs = {}, cf:, cf_value: nil)
  project = Project.find_by(identifier: identifier)
  if project.nil?
    project = Project.new(name: name, identifier: identifier)
    project.custom_field_values = {cf.id.to_s => cf_value} if cf_value
    project.enabled_module_names = %w[issue_tracking time_tracking]
    attrs.each { |k, v| project.send("#{k}=", v) }
    project.save!
    puts "[seed] project created: #{name} (#{identifier})"
  else
    puts "[seed] project exists: #{name} (#{identifier})"
  end
  project
end

# 6. 项目（覆盖三种分类、未分类、归档、私有、子项目）
p_research_a = ensure_project('research-a', '调研项目A', {is_public: true}, cf: cf, cf_value: '调研')
p_research_b = ensure_project('research-b', '调研项目B', {is_public: true}, cf: cf, cf_value: '调研')
p_dev_c = ensure_project('dev-c', '开发项目C', {is_public: false}, cf: cf, cf_value: '开发')
p_dev_c_child = ensure_project('dev-c-child', '开发项目C-子项目', {is_public: false, parent_id: nil}, cf: cf, cf_value: '开发')
p_dev_d = ensure_project('dev-d', '开发项目D', {is_public: true}, cf: cf, cf_value: '开发')
p_maint_e = ensure_project('maintenance-e', '维护项目E', {is_public: true}, cf: cf, cf_value: '维护')
p_uncat_f = ensure_project('uncategorized-f', '未分类项目F', {is_public: true}, cf: cf, cf_value: nil)
p_archive_g = ensure_project('archived-g', '归档项目G', {is_public: true}, cf: cf, cf_value: '开发')
p_private_h = ensure_project('private-h', '私有项目H', {is_public: false}, cf: cf, cf_value: '维护')

# 子项目关系（避免项目已存在时未设置 parent）
if p_dev_c_child.parent_id != p_dev_c.id
  p_dev_c_child.parent_id = p_dev_c.id
  p_dev_c_child.save!
  say "child project parent set"
end

# 归档项目 G（status: 9 = archived）
unless p_archive_g.status == Project::STATUS_ARCHIVED
  p_archive_g.status = Project::STATUS_ARCHIVED
  p_archive_g.save!
  say "project archived: #{p_archive_g.name}"
end

# 7. 成员关系
def ensure_member(project, user, role)
  member = Member.find_or_initialize_by(project_id: project.id, user_id: user.id)
  member.roles = [role]
  member.save!
  puts "[seed] member: #{user.login} -> #{project.identifier} (#{role.name})"
end

ensure_member(p_dev_c, dev1, dev_role)
ensure_member(p_dev_c, viewer1, readonly_role)
ensure_member(p_dev_c, reporter1, reporter_role)
ensure_member(p_research_a, dev1, dev_role)
ensure_member(p_research_a, dev2, dev_role)
ensure_member(p_private_h, dev2, dev_role)

# 8. 任务
feature = Tracker.find_by(name: '功能') || Tracker.first
bug = Tracker.find_by(name: '错误') || feature
priority = IssuePriority.where(is_default: true).first || IssuePriority.first

def ensure_issue(project, tracker, priority, subject, status:, author:, assigned_to: nil,
                 is_private: false, parent: nil, spent_hours: nil)
  issue = Issue.find_by(project_id: project.id, subject: subject)
  if issue
    puts "[seed] issue exists: #{subject}"
    return issue
  end
  issue = Issue.new(project: project, tracker: tracker, priority: priority,
                    subject: subject, status: status, author: author,
                    assigned_to: assigned_to, is_private: is_private,
                    parent_issue_id: parent&.id)
  issue.save!
  puts "[seed] issue created: ##{issue.id} #{subject}"
  issue
end

open_status = IssueStatus.find_by(name: '进行中') || IssueStatus.find_by(is_closed: false)
new_status = IssueStatus.find_by(name: '新建') || open_status
feedback_status = IssueStatus.find_by(name: '反馈') || open_status
closed_default = IssueStatus.find_by(name: '已关闭') || IssueStatus.find_by(is_closed: true)
rejected_status = IssueStatus.find_by(name: '已拒绝') || closed_default

# 调研项目A
a1 = ensure_issue(p_research_a, feature, priority, '调研任务：需求访谈', status: open_status, author: dev1, assigned_to: dev1)
a2 = ensure_issue(p_research_a, feature, priority, '调研任务：竞品分析', status: new_status, author: admin, assigned_to: dev2)
a3 = ensure_issue(p_research_a, bug, priority, '调研任务：旧数据核对', status: closed_default, author: admin, assigned_to: dev1)
if a1 && a1.time_entries.empty?
  activity = TimeEntryActivity.where(project_id: nil).first || TimeEntryActivity.first
  te = TimeEntry.new(project: p_research_a, issue: a1, user: dev1, hours: 2.0,
                     spent_on: Date.today - 1, activity: activity, comments: '需求访谈工时')
  te.save!
  say "time entry created on ##{a1.id}"
end

# 开发项目C（私有，只有 dev1/viewer1/report1 可见）
c1 = ensure_issue(p_dev_c, feature, priority, '开发任务：接口联调', status: open_status, author: dev1, assigned_to: dev1)
c2 = ensure_issue(p_dev_c, feature, priority, '开发任务：页面优化', status: new_status, author: admin, assigned_to: reporter1)
c3 = ensure_issue(p_dev_c, bug, priority, '开发任务：私有缺陷修复', status: open_status, author: admin, assigned_to: dev1, is_private: true)
c4 = ensure_issue(p_dev_c, feature, priority, '开发任务：等待反馈', status: feedback_status, author: admin, assigned_to: reporter1)
c5 = ensure_issue(p_dev_c, feature, priority, '已关闭任务：历史需求', status: closed_default, author: admin, assigned_to: dev1)
c6 = ensure_issue(p_dev_c, bug, priority, '已拒绝任务：废弃需求', status: rejected_status, author: admin, assigned_to: dev1)
c7 = ensure_issue(p_dev_c, feature, priority, '自定义关闭状态任务', status: closed_status, author: admin, assigned_to: dev1)
ensure_issue(p_dev_c, feature, priority, '子任务：联调子项', status: new_status, author: dev1, assigned_to: dev1, parent: c1)

# 子项目任务（不应混入 C 的列表）
ensure_issue(p_dev_c_child, feature, priority, '子项目任务：不应出现在开发项目C', status: new_status, author: admin)

# 开发项目D（切换项目测试）
ensure_issue(p_dev_d, feature, priority, '开发任务D：独立项目', status: new_status, author: admin)

# 维护项目E
ensure_issue(p_maint_e, bug, priority, '维护任务E：线上问题', status: open_status, author: admin)

# 未分类项目F
ensure_issue(p_uncat_f, feature, priority, '未分类任务F：待归类', status: new_status, author: admin)

# 归档项目G
ensure_issue(p_archive_g, feature, priority, '归档任务G：应隐藏', status: new_status, author: admin)

# 私有项目H（dev1 不可见）
ensure_issue(p_private_h, feature, priority, '私有任务H：不应泄漏', status: new_status, author: admin, assigned_to: dev2)

# 让 C 的开放任务更新时间错开，验证排序
[c1, c2, c3, c4].compact.each_with_index do |issue, idx|
  issue.update_column(:updated_on, Time.now - idx.hours)
end

say "done: projects=#{Project.count} issues=#{Issue.count} users=#{User.count} custom_fields=#{ProjectCustomField.count}"
say "project type field id=#{cf.id} name=#{cf.name} values=#{cf.possible_values.inspect}"
say "group summary: #{Project.visible(admin).pluck(:id, :name).inspect}"
