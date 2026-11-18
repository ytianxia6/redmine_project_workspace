# frozen_string_literal: true

module ProjectWorkspaceHelper
  SCOPES = %w[open in_progress assigned_to_me].freeze
  COLUMNS = %w[id subject tracker status priority assigned_to updated_on spent_hours].freeze

  # URL of the issues endpoint for AJAX panel reloads.
  def ws_issues_url(project, result = nil, overrides = {})
    params = {
      :project_id => project.id,
      :scope => result&.scope,
      :sort => result&.sort_param,
      :per_page => ws_per_page_param(result)
    }.compact
    project_workspace_issues_path(params.merge(overrides.compact))
  end

  def ws_per_page_param(result)
    return nil if result.nil?
    return nil if result.per_page == ProjectWorkspace::IssuesFinder::DEFAULT_PER_PAGE

    result.per_page
  end

  def ws_scope_label(scope)
    case scope
    when 'in_progress'
      l(:label_project_workspace_in_progress)
    when 'assigned_to_me'
      l(:label_project_workspace_assigned_to_me)
    else
      l(:label_project_workspace_all_open)
    end
  end

  def ws_scope_link(project, result, scope)
    active = result.scope == scope
    link_to ws_scope_label(scope),
            ws_issues_url(project, result, :scope => scope, :page => nil),
            :class => ['ws-filter', ('active' if active)].compact.join(' '),
            :data => { :ws_nav => 'panel' },
            :'aria-current' => (active ? 'true' : nil)
  end

  def ws_column_label(column)
    case column
    when 'id' then l(:field_id, :default => '#')
    when 'subject' then l(:field_subject)
    when 'tracker' then l(:field_tracker)
    when 'status' then l(:field_status)
    when 'priority' then l(:field_priority)
    when 'assigned_to' then l(:field_assigned_to)
    when 'updated_on' then l(:field_updated_on)
    when 'spent_hours' then l(:label_spent_time)
    end
  end

  def ws_columns(result)
    columns = %w[id subject tracker status priority assigned_to updated_on]
    columns << 'spent_hours' if result.show_spent_hours?
    columns
  end

  def ws_sort_link(project, result, column)
    current_direction = result.sort.assoc(column)&.last
    next_direction = current_direction == 'asc' ? 'desc' : 'asc'
    css = ['ws-sort']
    label = ws_column_label(column)
    if current_direction
      css << 'sorted'
      label = safe_join([label, content_tag(:span, current_direction == 'asc' ? '▲' : '▼', :class => 'ws-sort__indicator')])
    end
    link_to label,
            ws_issues_url(project, result, :sort => "#{column}:#{next_direction}", :page => nil),
            :class => css.join(' '),
            :data => { :ws_nav => 'panel' }
  end

  def ws_pagination(project, result)
    return ''.html_safe if result.count.zero?

    pagination_links_each(result.paginator, result.count) do |text, params|
      link_to text,
              project_workspace_issues_path(
                { :project_id => project.id,
                  :scope => result.scope,
                  :sort => result.sort_param }.merge(params)
              ),
              :class => 'ws-page-link',
              :data => { :ws_nav => 'panel' }
    end
  end

  # Native "log time" URL of a Redmine issue (used as a no-JS fallback link,
  # the context menu itself is Redmine's native one).
  def ws_log_time_path(issue)
    return nil unless issue.time_loggable?

    new_issue_time_entry_path(issue)
  end

  def ws_new_issue_allowed?(project)
    project.module_enabled?(:issue_tracking) &&
      User.current.allowed_to?(:add_issues, project)
  end

  # Renders one issue cell. Only the API-safe attributes already loaded by
  # IssueQuery are used (no extra queries).
  def ws_cell_content(issue, column)
    case column
    when 'id'
      link_to issue.id, issue_path(issue)
    when 'subject'
      link_to issue.subject, issue_path(issue), :class => 'ws-issue-subject'
    when 'tracker'
      issue.tracker.name
    when 'status'
      content_tag(:span, issue.status.name, :class => 'ws-status')
    when 'priority'
      content_tag(:span, issue.priority.name, :class => 'ws-priority')
    when 'assigned_to'
      issue.assigned_to ? link_to_user(issue.assigned_to) : ''.html_safe
    when 'updated_on'
      format_time(issue.updated_on)
    when 'spent_hours'
      issue.spent_hours ? l_hours_short(issue.spent_hours) : ''.html_safe
    else
      ''.html_safe
    end
  end
end
