# frozen_string_literal: true

# Gives the migration (sync) user the rights it needs to replay a work item's history:
#   1. a role "ADO Migration" that may add/edit work packages and change status,
#   2. ALL status transitions for that role in every workflow (the replay jumps New -> Confirmed -> Scheduled -> Closed ...),
#   3. membership of the sync user in every project with that role,
#   4. the project modules the migration writes into: time tracking ("costs": spent time) and backlogs (sprints).
# Without it an admin who is not a member only has the "Non member" role, whose workflow rejects most transitions (HTTP 422).
# Run inside the OpenProject app (self-hosted), dry run first. NOT tested against a live instance: read the dry-run output.
#   docker compose exec web bundle exec rails runner /path/migration_role.rb                         # dry run
#   docker compose exec -e APPLY=1 web bundle exec rails runner /path/migration_role.rb
# SYNC_LOGIN / SYNC_USER_ID override the user (default: the owner of the API token, vuna@etc.vn, id 5). Idempotent.
# Run it on the instance behind the sync's OP_URL (qlda.etc.vn): check the 'instance:' line against the numbers printed below it.

login = ENV.fetch("SYNC_LOGIN", "admin")
apply = ENV["APPLY"] == "1"
puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to write)")

puts "instance: host_name=#{Setting.host_name} users=#{User.count} projects=#{Project.count} work_packages=#{WorkPackage.count}"
puts "expected for the ADO migration target: users=340 projects=150 work_packages>=44 (WP 40 is '[BE]'): #{WorkPackage.find_by(id: 40)&.subject.inspect}"
user = (ENV["SYNC_USER_ID"] ? User.find_by(id: ENV["SYNC_USER_ID"]) : User.where("LOWER(login) = ?", login.downcase).first) or
       abort "no user #{login} on THIS instance: wrong OpenProject (the migration target has users=340)? set SYNC_USER_ID to override"
wanted = %i[view_project view_work_packages add_work_packages edit_work_packages change_work_package_status manage_subtasks
            add_work_package_comments assign_versions move_work_packages view_sprints manage_sprint_items
            view_time_entries log_time log_own_time]
known = wanted.select { |p| OpenProject::AccessControl.permission(p) }
puts "permissions not known in this version, skipped: #{(wanted - known).join(', ')}" if known.size != wanted.size

role = ProjectRole.find_by(name: "ADO Migration")
if role
  missing_perms = known - role.permissions.map(&:to_sym)
  puts "role exists: #{role.id}#{missing_perms.any? ? "; add permissions: #{missing_perms.join(', ')}" : ''}"
  role.add_permission!(*missing_perms) if apply && missing_perms.any?
else
  puts "create role ADO Migration with #{known.join(', ')}"
  if apply
    role = ProjectRole.new(name: "ADO Migration")  # Role is abstract: its type must be ProjectRole
    role.permissions = known
    role.save!
  end
end

# 2) every transition between two different statuses, for every workflow, not tied to author/assignee
statuses = Status.pluck(:id)
added = 0
Workflow.find_each do |workflow|
  existing = role ? workflow.status_transitions.where(role_id: role.id).pluck(:old_status_id, :new_status_id, :author, :assignee) : []
  statuses.product(statuses).each do |from, to|
    next if from == to || existing.include?([from, to, false, false])

    added += 1
    next unless apply

    workflow.status_transitions.create!(role:, old_status_id: from, new_status_id: to, author: false, assignee: false)
  end
end
puts "[workflows] transitions #{apply ? 'added' : 'to add'}: #{added}"

# 3) membership in every project
members = 0
Project.find_each do |project|
  member = Member.find_by(project:, user_id: user.id)
  next if member && role && member.roles.include?(role)

  members += 1
  puts "[#{project.identifier}] add #{login} as ADO Migration"
  next unless apply

  member ||= Member.new(project:, principal: user)
  member.roles << role unless member.roles.include?(role)
  member.save!
end
puts "done: memberships #{apply ? 'added' : 'to add'}=#{members}"

# 4) modules: without "costs" OP refuses the spent-time entries, without "backlogs" there are no sprints
wanted_modules = %w[costs backlogs]
enabled = 0
Project.find_each do |project|
  missing = wanted_modules - project.enabled_module_names
  next if missing.empty?

  enabled += 1
  puts "[#{project.identifier}] enable modules #{missing.join(', ')}"
  next unless apply

  project.enabled_module_names = project.enabled_module_names + missing
  project.save!(validate: false)
end
puts "done: projects whose modules #{apply ? 'were' : 'would be'} enabled=#{enabled}"
