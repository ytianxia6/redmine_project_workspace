# frozen_string_literal: true

# 开发环境：切换项目分类字段是否多值（验证工作台的配置校验）
mode = ARGV.first
raise 'usage: on|off' unless %w[on off].include?(mode)

field = ProjectCustomField.find_by(:name => '项目类型')
raise 'field missing' if field.nil?

field.multiple = (mode == 'on')
field.save!
puts "field #{field.id} multiple=#{field.multiple}"
