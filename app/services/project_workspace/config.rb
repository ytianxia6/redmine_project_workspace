# frozen_string_literal: true

module ProjectWorkspace
  # Reads the plugin configuration (the project custom field used for grouping)
  # and validates that it can be used by the workspace.
  module Config
    SETTING_KEY = 'project_custom_field_id'

    module_function

    def settings
      Setting.plugin_redmine_project_workspace || {}
    end

    def custom_field_id
      settings[SETTING_KEY].to_s
    end

    # Returns the configured ProjectCustomField or nil when not configured/missing.
    def custom_field
      return nil if custom_field_id.blank?

      ProjectCustomField.find_by(:id => custom_field_id)
    end

    # Returns nil when the configuration is usable, otherwise a symbol:
    #   :not_configured, :not_found, :not_list, :multiple
    def problem
      id = custom_field_id
      return :not_configured if id.blank?

      field = ProjectCustomField.find_by(:id => id)
      return :not_found if field.nil?
      return :not_list unless field.field_format == 'list'
      return :multiple if field.multiple?

      nil
    end

    def usable?
      problem.nil?
    end

    # The field usable for grouping, nil when the configuration is invalid.
    def usable_field
      usable? ? custom_field : nil
    end
  end
end
