# frozen_string_literal: true

Redmine::Plugin.register :redmine_project_workspace do
  name 'Redmine Project Workspace'
  author 'Redmine Project Workspace'
  description 'Project workspace: projects grouped by a project custom field, with native issues list, context menu and time logging.'
  version '0.1.0'
  url 'https://example.invalid/redmine_project_workspace'
  author_url 'https://example.invalid'

  requires_redmine :version_or_higher => '7.0.0'

  settings :default => {
    'project_custom_field_id' => ''
  }, :partial => 'settings/project_workspace'

  menu :top_menu, :project_workspace,
       { :controller => 'project_workspace', :action => 'index' },
       :caption => :label_project_workspace,
       :if => Proc.new { User.current.logged? || !Setting.login_required? },
       :after => :projects
end
