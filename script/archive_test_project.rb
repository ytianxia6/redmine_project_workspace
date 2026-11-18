# frozen_string_literal: true

project = Project.find_by(:identifier => 'archived-g')
raise 'project missing' if project.nil?

project.status = Project::STATUS_ARCHIVED
project.save!
puts "project #{project.identifier} status=#{project.status} archived=#{project.archived?}"
