# frozen_string_literal: true

# Creates one OpenProject PORTFOLIO per ADO collection (API v3 lists portfolios but always creates plain projects). Input: JSON lines from
#   docker compose run --rm --no-deps -T sync python -m ado2op.cli export-portfolios > portfolios.jsonl
# {"name": "MPS", "identifier": "mps", "description": "..."}
# Once they exist, the project sync (service `sync`) moves every ADO project under the portfolio of its collection on its next cycle.
# Uses the normal create service (contracts, default modules, Enterprise check) as the user of the API token.
# Run inside the OpenProject app, dry run first. NOT tested against a live instance: read the dry-run output.
#   docker cp portfolios.jsonl openproject-production-web-1:/tmp/portfolios.jsonl
#   docker exec openproject-production-web-1 bundle exec rails runner /tmp/create_portfolios.rb                 # dry run
#   docker exec -e APPLY=1 openproject-production-web-1 bundle exec rails runner /tmp/create_portfolios.rb
# Idempotent (by identifier). SYNC_LOGIN overrides the user (default vuna@etc.vn).

require "json"

file = ENV.fetch("FILE", "/tmp/portfolios.jsonl")
apply = ENV["APPLY"] == "1"
login = ENV.fetch("SYNC_LOGIN", "vuna@etc.vn")
puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to write)")
puts "instance: host_name=#{Setting.host_name} projects=#{Project.count} portfolios=#{Project.where(workspace_type: 'portfolio').count}"
user = User.where("LOWER(login) = ?", login.downcase).first or abort "no user #{login} on this instance"

stats = Hash.new(0)
File.foreach(file) do |line|
  row = JSON.parse(line)
  existing = Project.find_by(identifier: row["identifier"])
  if existing&.portfolio?
    stats[:exists] += 1
    puts "exists: #{row['identifier']} (id #{existing.id})"
    next
  elsif existing
    stats[:identifier_taken] += 1
    warn "identifier #{row['identifier']} is already used by a #{existing.workspace_type} (id #{existing.id}): rename one of them first"
    next
  end

  puts "create portfolio #{row['name']} (#{row['identifier']})"
  stats[:created] += 1
  next unless apply

  result = Projects::CreateService.new(user:).call(name: row["name"], identifier: row["identifier"], workspace_type: "portfolio",
                                                   public: false, description: row["description"])
  next if result.success?

  stats[:created] -= 1
  stats[:failed] += 1
  warn "#{row['identifier']}: #{result.errors.full_messages.join('; ')}"
end
puts "done: #{stats.map { |k, v| "#{k}=#{v}" }.join(' ')}"
