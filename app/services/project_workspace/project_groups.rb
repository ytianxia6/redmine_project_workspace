# frozen_string_literal: true

module ProjectWorkspace
  # Groups the projects visible by a user by the values of a project custom field.
  #
  # Rules (documented in README):
  # * only active projects the user can view issues on are listed;
  # * the field value is used only when the user is allowed to see that field on
  #   the project (ProjectCustomField#visible_by?), otherwise the project is
  #   grouped as "uncategorized" so that hidden values are never disclosed;
  # * blank, unknown and multi-valued values fall back to "uncategorized";
  # * group order follows the field options order, "uncategorized" always last.
  class ProjectGroups
    UNCATEGORIZED = :uncategorized

    Group = Struct.new(:key, :label, :projects, :type, keyword_init: true) do
      def count
        projects.size
      end

      def uncategorized?
        type == :uncategorized
      end
    end

    Result = Struct.new(:groups, :field, :problem, keyword_init: true) do
      def empty?
        groups.empty?
      end

      def project_count
        groups.sum(&:count)
      end

      def first_project
        groups.first&.projects&.first
      end
    end

    def initialize(user:, field:)
      @user = user
      @field = field
    end

    def call
      return Result.new(:groups => [], :field => @field, :problem => :not_configured) if @field.nil?

      buckets = Hash.new { |hash, key| hash[key] = [] }
      visible_projects.each do |project|
        buckets[bucket_key(project)] << project
      end

      groups = []
      option_values.each do |value|
        next unless buckets.key?(value)

        groups << Group.new(:key => value, :label => value, :projects => buckets[value], :type => :value)
      end
      if buckets.key?(UNCATEGORIZED)
        groups << Group.new(:key => UNCATEGORIZED,
                            :label => I18n.t(:label_project_workspace_uncategorized),
                            :projects => buckets[UNCATEGORIZED],
                            :type => :uncategorized)
      end

      Result.new(:groups => groups, :field => @field, :problem => nil)
    end

    private

    def visible_projects
      Project.visible(@user).
        active.
        allowed_to(@user, :view_issues).
        preload(:custom_values).
        order(:name, :id).
        to_a
    end

    def option_values
      @option_values ||= Array(@field&.possible_values).map { |value| value.to_s.strip }.reject(&:blank?)
    end

    def bucket_key(project)
      value = field_value(project)
      value.presence || UNCATEGORIZED
    end

    # Returns the normalized field value, or nil when it must not be used.
    def field_value(project)
      return nil unless @field.visible_by?(project, @user)

      raw = project.custom_field_value(@field)
      return nil if raw.nil?

      if raw.is_a?(Array)
        # The configured field is expected to be single-valued (validated by Config).
        # If a multi-valued field is used anyway, never pick a value silently.
        return nil unless raw.size == 1

        raw = raw.first
      end

      value = raw.to_s.strip
      return nil if value.empty?
      return nil unless option_values.include?(value)

      value
    end
  end
end
