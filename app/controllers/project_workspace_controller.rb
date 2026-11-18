# frozen_string_literal: true

# Read-only workspace controller: project tree + open issue list of a project.
# No write endpoint is added; issue creation and time logging use Redmine's
# native controllers.
class ProjectWorkspaceController < ApplicationController
  menu_item :project_workspace
  helper :issues

  def index
    load_workspace_context
    if params[:project_id].present?
      @project = find_workspace_project(params[:project_id])
      return if performed?
    end
    @project ||= @groups_result.first_project
    @result = issues_result(@project) if @project
    render :index
  end

  def issues
    project = find_workspace_project(params[:project_id])
    return if performed?

    @result = issues_result(project)
    if request.xhr?
      render :partial => 'project_workspace/issues_panel',
             :locals => { :project => project, :result => @result }
    else
      @project = project
      load_workspace_context
      render :index
    end
  end

  private

  def load_workspace_context
    @field_problem = ProjectWorkspace::Config.problem
    @field = ProjectWorkspace::Config.usable_field
    @groups_result = ProjectWorkspace::ProjectGroups.new(
      :user => User.current, :field => @field
    ).call
  end

  def issues_result(project)
    ProjectWorkspace::IssuesFinder.new(
      :project => project, :user => User.current, :params => params
    ).call
  end

  # Finds a project the current user may view issues on.
  # Renders 403/404 (native behaviour) and returns nil when not allowed.
  def find_workspace_project(id)
    project = Project.find_by(:id => id)
    render_404 if project.nil? && !performed?
    return nil if performed?
    unless User.current.allowed_to?(:view_issues, project)
      deny_access
      return nil
    end
    # Archived projects are hidden from the workspace, including for admins
    # who would otherwise be allowed to read them.
    if project.archived?
      render_403(:message => :notice_not_authorized_archived_project)
      return nil
    end

    project
  end
end
