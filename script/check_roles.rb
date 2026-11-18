# frozen_string_literal: true

puts "trackers=#{Tracker.order(:id).map(&:name).join(',')}"
puts "statuses=#{IssueStatus.order(:id).map { |s| "#{s.name}(#{s.id},closed=#{s.is_closed})" }.join(' ')}"
Role.order(:id).each do |r|
  puts "role #{r.id} #{r.name} builtin=#{r.builtin} perms=#{r.permissions.sort.join(',')}"
end
puts "non_member_perms=#{Role.non_member.permissions.sort.join(',')}"
puts "anonymous_perms=#{Role.anonymous.permissions.sort.join(',')}"
puts "modules=#{Redmine::AccessControl.available_project_modules.join(',')}"
