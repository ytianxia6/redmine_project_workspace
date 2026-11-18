# frozen_string_literal: true

# 开发环境：切换项目分类字段的角色可见性，用于验证“隐藏值不泄漏”
# 用法：rails runner script/toggle_field_visibility.rb RAILS_ENV=production [restricted|public]
mode = ARGV.first || 'restricted'
cf = ProjectCustomField.find_by(:name => '项目类型')
raise 'custom field missing' if cf.nil?

case mode
when 'restricted'
  developer = Role.find_by(:name => '开发人员')
  cf.visible = false
  cf.role_ids = [developer.id]
  cf.save!
  puts "field #{cf.id} restricted to role #{developer.name}"
when 'public'
  cf.visible = true
  cf.role_ids = []
  cf.save!
  puts "field #{cf.id} visible to everyone"
else
  raise "unknown mode #{mode}"
end
