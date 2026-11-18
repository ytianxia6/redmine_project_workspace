# frozen_string_literal: true

# Plugin routes are loaded by Redmine after the core routes.
# Keep the workspace read-only: no custom write endpoints.
get 'project_workspace', :to => 'project_workspace#index', :as => 'project_workspace'
get 'project_workspace/issues', :to => 'project_workspace#issues', :as => 'project_workspace_issues'
