# frozen_string_literal: true

# Deletes projects/portfolios by identifier, WITH their sub-projects, work packages and members. IRREVERSIBLE: back up the DB first.
# Input, either:
#   IDENTIFIERS=mps,abc   comma separated
#   FILE=/tmp/portfolios.jsonl   JSON lines with an "identifier" key (same files the create_* scripts use)
# Uses the normal delete service as the user (contracts, cleanup of members/storages/work packages), like the UI does.
#   docker cp delete_projects.rb openproject-production-web-1:/tmp/delete_projects.rb
#   docker exec -e IDENTIFIERS=mps openproject-production-web-1 bundle exec rails runner /tmp/delete_projects.rb            # dry run
#   docker exec -e IDENTIFIERS=mps -e APPLY=1 openproject-production-web-1 bundle exec rails runner /tmp/delete_projects.rb
# SYNC_LOGIN overrides the user (default vuna@etc.vn). Not tested against a live instance: read the dry-run output.

require "json"

apply = ENV["APPLY"] == "1"
login = ENV.fetch("SYNC_LOGIN", "vuna@etc.vn")
identifiers =
  if ENV["IDENTIFIERS"]
    ENV["IDENTIFIERS"].split(",").map(&:strip).reject(&:empty?)
  elsif ENV["FILE"]
    File.foreach(ENV["FILE"]).map { |l| JSON.parse(l)["identifier"] }.compact
  else
    abort "set IDENTIFIERS=a,b or FILE=/path/rows.jsonl"
  end

puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to delete)")
user = User.where("LOWER(login) = ?", login.downcase).first or abort "no user #{login} on this instance"

stats = Hash.new(0)
identifiers.each do |identifier|
  project = Project.find_by(identifier:)
  unless project
    stats[:missing] += 1
    puts "missing: #{identifier}"
    next
  end

  # ponytail: counts only, no per-project confirmation; the dry run is the safety net
  puts "delete #{project.workspace_type} #{identifier} (id #{project.id}): " \
       "#{project.descendants.count} sub-projects, #{WorkPackage.where(project_id: [project.id, *project.descendants.ids]).count} work packages"
  next unless apply

  result = Projects::DeleteService.new(user:, model: project).call
  if result.success?
    stats[:deleted] += 1
  else
    stats[:failed] += 1
    warn "#{identifier}: #{result.errors.full_messages.join('; ')}"
  end
end
puts "done: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
