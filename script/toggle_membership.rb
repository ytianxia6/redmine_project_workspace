# frozen_string_literal: true

# 开发环境：撤销/恢复用户对项目的成员关系，用于验证异步请求的实时鉴权
# 用法：rails runner script/toggle_membership.rb revoke|restore dev1 dev-c

mode, login, identifier = ARGV
raise 'usage: revoke|restore login identifier' if mode.blank? || login.blank? || identifier.blank?

user = User.find_by(:login => login)
project = Project.find_by(:identifier => identifier)
raise 'user/project missing' if user.nil? || project.nil?

case mode
when 'revoke'
  Member.where(:project_id => project.id, :user_id => user.id).destroy_all
  puts "revoked #{login} from #{identifier}"
when 'restore'
  member = Member.find_or_initialize_by(:project_id => project.id, :user_id => user.id)
  member.roles = [Role.find_by(:name => '开发人员')]
  member.save!
  puts "restored #{login} on #{identifier}"
else
  raise "unknown mode #{mode}"
end
puts "member?=#{project.members.exists?(:user_id => user.id)}"
