# frozen_string_literal: true

# Re-attributes migrated journals to the real ADO author. The API cannot set the user of a journal (it is always the API token's
# user), so after the replay we fix journals.user_id from a file written by:
#   docker compose run --rm --no-deps -T sync python -m ado2op.cli export-journal-users > journal_users.jsonl
# Each line: {"wp": <work package id>, "version": <journal version>, "login": "<user login>"}.
# Run inside the OpenProject app, dry run first. NOT tested against a live instance: read the dry-run output.
#   docker cp journal_users.jsonl openproject-production-web-1:/tmp/journal_users.jsonl
#   docker exec openproject-production-web-1 bundle exec rails runner /tmp/journal_users.rb                 # dry run
#   docker exec -e APPLY=1 openproject-production-web-1 bundle exec rails runner /tmp/journal_users.rb
# FILE overrides the path. Touches only journals.user_id (no callbacks, no timestamps). Idempotent.

require "json"

file = ENV.fetch("FILE", "/tmp/journal_users.jsonl")
apply = ENV["APPLY"] == "1"
puts(apply ? "APPLY mode" : "DRY RUN (set APPLY=1 to write)")
puts "instance: host_name=#{Setting.host_name} users=#{User.count} projects=#{Project.count} work_packages=#{WorkPackage.count}"

users = Hash.new { |h, login| h[login] = User.where("LOWER(login) = ?", login.downcase).pick(:id) }
rows = File.foreach(file).map { |l| JSON.parse(l) }
changed = same = missing_user = missing_journal = 0
unknown = Hash.new(0)

rows.each do |row|
  uid = users[row["login"]]
  unless uid
    missing_user += 1
    unknown[row["login"]] += 1
    next
  end
  journal = Journal.find_by(journable_type: "WorkPackage", journable_id: row["wp"], version: row["version"])
  unless journal
    missing_journal += 1
    next
  end
  if journal.user_id == uid
    same += 1
  else
    changed += 1
    journal.update_columns(user_id: uid) if apply
  end
end

puts "rows=#{rows.size} #{apply ? 'updated' : 'to update'}=#{changed} already_correct=#{same} journal_not_found=#{missing_journal} user_not_found=#{missing_user}"
unknown.sort_by { |_, n| -n }.first(20).each { |login, n| puts "  no OpenProject user #{login}: #{n} journals" }
