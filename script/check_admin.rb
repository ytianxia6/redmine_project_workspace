# frozen_string_literal: true

# 仅用于开发环境：确认 admin 账号与初始数据状态
u = User.find_by_login('admin')
puts "admin_exists=#{!u.nil?}"
puts "admin_pwd_ok=#{u ? u.check_password?(ENV.fetch('TEST_ADMIN_PASSWORD', '11111111')) : false}"
puts "admin_status=#{u&.status}"
puts "trackers=#{Tracker.count} statuses=#{IssueStatus.count} roles=#{Role.count}"
