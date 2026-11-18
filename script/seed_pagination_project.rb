# frozen_string_literal: true

# 开发环境：分页/排序测试项目（30 条未关闭 + 2 条关闭任务）
cf = ProjectCustomField.find_by(:name => '项目类型')
project = Project.find_by(:identifier => 'workspace-pagination')
if project.nil?
  project = Project.new(:name => '工作台分页项目P', :identifier => 'workspace-pagination',
                        :is_public => true)
  project.custom_field_values = { cf.id.to_s => '开发' }
  project.enabled_module_names = %w[issue_tracking time_tracking]
  project.save!
  puts "project created: #{project.id}"
end

tracker = Tracker.find_by(:name => '功能') || Tracker.first
priority = IssuePriority.where(:is_default => true).first || IssuePriority.first
open_status = IssueStatus.find_by(:name => '进行中')
closed_status = IssueStatus.find_by(:name => '已关闭')
author = User.find_by(:login => 'admin')

30.times do |i|
  subject = format('分页任务 %02d', i + 1)
  next if Issue.exists?(:project_id => project.id, :subject => subject)

  Issue.create!(:project => project, :tracker => tracker, :priority => priority,
                :subject => subject, :status => open_status, :author => author)
end
2.times do |i|
  subject = format('分页已关闭任务 %02d', i + 1)
  next if Issue.exists?(:project_id => project.id, :subject => subject)

  Issue.create!(:project => project, :tracker => tracker, :priority => priority,
                :subject => subject, :status => closed_status, :author => author)
end
puts "project #{project.identifier} issues=#{project.issues.count} open=#{project.issues.open.count}"
