# frozen_string_literal: true

# Enables the required work item types in OpenProject: for NEW projects (default flag) and EXISTING projects.
# API v3 cannot do this, so run it inside the OpenProject app (self-hosted), e.g.:
#   docker compose exec web bundle exec rails runner /path/enable_project_types.rb          # dry run
#   docker compose exec -e APPLY=1 web bundle exec rails runner /path/enable_project_types.rb
# Types are matched by name, case-insensitively. Idempotent. TYPES overrides the list.

wanted = ENV.fetch("TYPES", "Task,Summary task,Epic,Bug,Milestone,Feature,User story").split(",").map(&:strip)
apply = ENV["APPLY"] == "1"
puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to write)")

types = wanted.index_with { |n| Type.where("LOWER(name) = LOWER(?)", n).first }
missing = types.select { |_, t| t.nil? }.keys
abort "Types missing in OpenProject, create them first: #{missing.join(', ')}" if missing.any?
variants = types.transform_values(&:default_variant)
puts "TYPE_VARIANTS=#{variants.map { |n, v| "#{n}:#{v.id}" }.join(',')}"

# 1) new projects get these types ticked automatically
variants.each do |name, variant|
  next if variant.enabled_in_new_projects?

  puts "[new projects] enable #{name}"
  variant.update!(enabled_in_new_projects: true) if apply
end

# 2) existing projects
user = User.system
added = 0
failed = 0
Project.find_each do |project|
  variants.each do |name, variant|
    next if project.project_types.exists?(type_id: variant.type_id) # already enabled (any variant)

    puts "[#{project.identifier}] add #{name}"
    next unless apply

    result = Projects::Types::AddService.new(user:, model: project).call(variant:)
    if result.success?
      added += 1
    else
      failed += 1
      warn "[#{project.identifier}] #{name}: #{result.message}"
    end
  end
end
puts "done: added=#{added} failed=#{failed}"
