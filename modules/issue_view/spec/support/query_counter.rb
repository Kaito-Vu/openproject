# frozen_string_literal: true

module IssueViewQueryCounter
  module_function

  def count(&block)
    count = 0
    ActiveSupport::Notifications.subscribed(->(*, payload) {
      next if payload[:name].in?(%w[SCHEMA TRANSACTION CACHE]) || payload[:cached]
      next if payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i)

      count += 1
    }, "sql.active_record", &block)
    count
  end
end
