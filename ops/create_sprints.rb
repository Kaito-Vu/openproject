# frozen_string_literal: true

# Creates one OpenProject sprint per ADO iteration (API v3 can read sprints but not create them). Input: JSON lines from
#   docker compose run --rm --no-deps -T sync python -m ado2op.cli export-iterations > iterations.jsonl
# {"op_project_id": 11, "name": "Release 1 / Sprint 3", "start": "2023-01-30", "finish": "2023-02-10", ...}
# The sync maps a work item's IterationPath to the sprint of that name in its project, so the names must stay as exported.
# Run inside the OpenProject app, dry run first. NOT tested against a live instance: read the dry-run output.
#   docker cp iterations.jsonl openproject-production-web-1:/tmp/iterations.jsonl
#   docker exec openproject-production-web-1 bundle exec rails runner /tmp/create_sprints.rb                 # dry run
#   docker exec -e APPLY=1 openproject-production-web-1 bundle exec rails runner /tmp/create_sprints.rb
# Idempotent (one sprint per project + name). Past sprints are created "completed", the others "in_planning" (OP allows one active).
# Sprint dates are mandatory in OP: an iteration without dates gets today's date and is listed at the end, to fix by hand.

require "json"

file = ENV.fetch("FILE", "/tmp/iterations.jsonl")
apply = ENV["APPLY"] == "1"
puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to write)")
puts "instance: host_name=#{Setting.host_name} projects=#{Project.count} sprints=#{Sprint.count}"

today = Date.current
stats = Hash.new(0)
undated = []
File.foreach(file) do |line|
  row = JSON.parse(line)
  project = Project.find_by(id: row["op_project_id"])
  unless project
    stats[:project_not_found] += 1
    next
  end
  start = row["start"] && Date.parse(row["start"])
  finish = row["finish"] && Date.parse(row["finish"])
  undated << "#{project.identifier}: #{row['name']}" unless start && finish
  start ||= finish || today
  finish ||= start
  start, finish = finish, start if finish < start
  status = finish < today ? "completed" : "in_planning"

  sprint = Sprint.find_or_initialize_by(project:, name: row["name"])
  if sprint.persisted? && sprint.start_date == start && sprint.finish_date == finish
    stats[:unchanged] += 1
    next
  end
  stats[sprint.persisted? ? :updated : :created] += 1
  next unless apply

  sprint.assign_attributes(start_date: start, finish_date: finish)
  sprint.status = status if sprint.new_record?
  begin
    sprint.save!
  rescue StandardError => e
    stats[:failed] += 1
    warn "[#{project.identifier}] #{row['name']}: #{e.message}"
  end
end
puts "done: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
puts "iterations without dates in ADO (#{undated.size}), given today's date:" if undated.any?
undated.first(50).each { |u| puts "  #{u}" }
