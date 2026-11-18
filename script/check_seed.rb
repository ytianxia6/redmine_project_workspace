# frozen_string_literal: true

# 打印测试数据的权限视角摘要（开发环境验证用）
pw = '11111111'
%w[admin dev1 dev2 viewer1 report1 outsider].each do |login|
  u = User.find_by_login(login)
  ok = u&.check_password?(pw)
  visible_projects = Project.where(id: Project.visible(u).pluck(:id)).order(:name).pluck(:identifier)
  line = "#{login}: pwd_ok=#{ok} admin=#{u&.admin?} projects=#{visible_projects.join(',')}"
  puts line
end

puts '--- groups by 项目类型 (admin, active only) ---'
cf = ProjectCustomField.find_by(name: '项目类型')
projects = Project.where(status: Project::STATUS_ACTIVE).where(id: Project.visible(User.find_by_login('admin')).pluck(:id))
projects.find_each do |p|
  value = p.custom_field_value(cf)
  puts "  #{p.identifier.ljust(18)} => #{value.is_a?(CustomValue) ? value.value : value}"
end

puts '--- open issue counts per project ---'
Issue.where(project_id: Project.where(status: Project::STATUS_ACTIVE).pluck(:id)).group(:project_id).count.each do |pid, count|
  project = Project.find(pid)
  open_count = project.issues.open.count
  puts "  #{project.identifier.ljust(18)} open=#{open_count} all=#{count}"
end
