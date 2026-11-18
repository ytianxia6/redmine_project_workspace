# frozen_string_literal: true

# 阶段A探测：验证 IssueQuery / 项目可见 scope / 子项目排除 / 私有任务可见性
def banner(text)
  puts "\n== #{text} =="
end

banner 'projects visible+active+allowed_to(view_issues)'
%w[admin dev1 dev2 viewer1 report1 outsider].each do |login|
  user = User.find_by_login(login)
  User.current = user
  scope = Project.visible(user).active.allowed_to(user, :view_issues)
  puts "#{login.ljust(8)} => #{scope.order(:name).pluck(:identifier).join(',')}"
end

banner 'IssueQuery on dev-c (private project)'
%w[admin dev1 viewer1 outsider].each do |login|
  user = User.find_by_login(login)
  User.current = user
  project = Project.find_by_identifier('dev-c')
  query = IssueQuery.new(project: project, name: 'workspace')
  query.add_filter('status_id', 'o', [''])
  query.add_filter('subproject_id', '!*', [''])
  query.column_names = %w[id subject tracker status priority assigned_to updated_on]
  query.sort_criteria = [['updated_on', 'desc'], ['id', 'desc']]
  puts "#{login.ljust(8)} count=#{query.issue_count} ids=#{query.issues.pluck(:id).inspect} " \
       "subjects=#{query.issues.map(&:subject).inspect}"
end

banner 'Issue.visible.open per project (admin)'
User.current = User.find_by_login('admin')
Project.order(:id).each do |p|
  puts "#{p.identifier.ljust(18)} visible_open=#{Issue.visible.open.where(project_id: p.id).count} " \
       "raw_open=#{p.issues.open.count} archived=#{p.archived?}"
end

banner 'assigned_to me filter'
User.current = User.find_by_login('dev1')
q2 = IssueQuery.new(project: Project.find_by_identifier('research-a'), name: 'x')
q2.add_filter('status_id', 'o', [''])
q2.add_filter('subproject_id', '!*', [''])
q2.add_filter('assigned_to_id', '=', ['me'])
puts "dev1 assigned_to me in research-a: #{q2.issues.map { |i| [i.id, i.subject, i.assigned_to&.login] }.inspect}"

banner 'multi-value / single custom field check'
cf = ProjectCustomField.find_by(name: '项目类型')
puts "cf=#{cf.id} format=#{cf.field_format} multiple=#{cf.multiple} visible=#{cf.visible} roles=#{cf.roles.map(&:name).inspect}"
puts "values sample: #{Project.find_by_identifier('dev-c').custom_field_value(cf).inspect}"
puts "uncat: #{Project.find_by_identifier('uncategorized-f').custom_field_value(cf).inspect}"
