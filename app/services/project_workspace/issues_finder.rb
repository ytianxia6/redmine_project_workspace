# frozen_string_literal: true

module ProjectWorkspace
  # Builds the open-issue list of a single project using Redmine's IssueQuery,
  # so that visibility rules (private issues, roles, tracker permissions),
  # status semantics (IssueStatus#is_closed) and sorting follow Redmine.
  #
  # Child projects are always excluded (single project scope).
  class IssuesFinder
    SCOPES = %w[open in_progress assigned_to_me].freeze
    DEFAULT_SCOPE = 'open'
    SORTABLE = %w[id subject tracker status priority assigned_to updated_on spent_hours].freeze
    DEFAULT_SORT = [%w[updated_on desc], %w[id desc]].freeze
    PER_PAGE_OPTIONS = [25, 50, 100].freeze
    DEFAULT_PER_PAGE = 25
    MAX_SORT_CRITERIA = 3

    Result = Struct.new(:issues, :count, :paginator, :scope, :sort, :per_page, :query, keyword_init: true) do
      def multiple_pages?
        paginator.multiple_pages?
      end

      def show_spent_hours?
        query.columns.map(&:name).include?('spent_hours')
      end

      def sort_param
        sort.map { |key, direction| "#{key}:#{direction}" }.join(',')
      end
    end

    def initialize(project:, user:, params: {})
      @project = project
      @user = user
      @params = params || {}
    end

    def call
      previous_user = User.current
      User.current = @user
      begin
        query = build_query
        count = query.issue_count
        paginator = Redmine::Pagination::Paginator.new(count, per_page, page)
        page_number = paginator.page
        if count.positive? && page_number > paginator.last_page
          page_number = paginator.last_page
          paginator = Redmine::Pagination::Paginator.new(count, per_page, page_number)
        end
        issues =
          if count.zero?
            []
          else
            query.issues(:offset => paginator.offset, :limit => paginator.per_page)
          end
        Result.new(:issues => issues, :count => count, :paginator => paginator,
                   :scope => scope, :sort => sort, :per_page => per_page, :query => query)
      ensure
        User.current = previous_user
      end
    end

    private

    def build_query
      query = IssueQuery.new(:name => 'project_workspace', :project => @project)
      query.add_filter('subproject_id', '!*', [''])
      case scope
      when 'assigned_to_me'
        query.add_filter('status_id', 'o', [''])
        query.add_filter('assigned_to_id', '=', ['me'])
      when 'in_progress'
        ids = in_progress_status_ids
        query.add_filter('status_id', '=', ids.map(&:to_s))
      else
        query.add_filter('status_id', 'o', [''])
      end
      query.column_names = column_names
      query.sort_criteria = sort
      query
    end

    # Open statuses except the status used as the initial (default) status of a
    # tracker. Redmine has no "in progress" status category, so this is the
    # documented and name-independent definition used by the workspace filter.
    def in_progress_status_ids
      ids = IssueStatus.where(:is_closed => false).order(:position).pluck(:id)
      initial_ids = Tracker.where.not(:default_status_id => nil).distinct.pluck(:default_status_id)
      initial_ids = [IssueStatus.order(:position).pick(:id)] if initial_ids.empty?
      ids -= initial_ids.compact
      ids.empty? ? [0] : ids
    end

    def column_names
      names = %w[id subject tracker status priority assigned_to updated_on]
      names << 'spent_hours' if @user.allowed_to?(:view_time_entries, @project)
      names
    end

    def scope
      @scope ||= begin
        value = @params[:scope].to_s
        SCOPES.include?(value) ? value : DEFAULT_SCOPE
      end
    end

    def sort
      @sort ||= begin
        criteria = @params[:sort].to_s.split(',').filter_map do |token|
          key, direction = token.split(':', 2)
          next unless SORTABLE.include?(key.to_s)

          [key.to_s, direction.to_s == 'asc' ? 'asc' : 'desc']
        end
        criteria = DEFAULT_SORT.map(&:dup) if criteria.empty?
        criteria = criteria.first(MAX_SORT_CRITERIA)
        criteria << %w[id desc] unless criteria.any? { |key, _| key == 'id' }
        criteria.first(MAX_SORT_CRITERIA)
      end
    end

    def per_page
      @per_page ||= begin
        value = @params[:per_page].to_i
        PER_PAGE_OPTIONS.include?(value) ? value : DEFAULT_PER_PAGE
      end
    end

    def page
      value = @params[:page].to_i
      value < 1 ? 1 : value
    end
  end
end
