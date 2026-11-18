# frozen_string_literal: true

# 开发环境：临时把所有项目设为私有（验证“0 个项目”空态），随后恢复。
# 用法：rails runner script/toggle_project_publicity.rb hide|restore
mode = ARGV.first

PUBLIC_IDENTIFIERS = %w[research-a research-b dev-d maintenance-e uncategorized-f archived-g workspace-pagination].freeze

case mode
when 'hide'
  Project.where.not(:identifier => %w[dev-c dev-c-child private-h]).update_all(:is_public => false)
  puts 'all projects set private'
when 'restore'
  Project.where(:identifier => PUBLIC_IDENTIFIERS).update_all(:is_public => true)
  Project.where(:identifier => %w[dev-c dev-c-child private-h]).update_all(:is_public => false)
  puts 'publicity restored'
else
  raise 'usage: hide|restore'
end
