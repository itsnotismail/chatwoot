# frozen_string_literal: true

# Comvor: adds an account's users to the inboxes they are missing from, for inboxes created before
# COMVOR_AUTO_INBOX_MEMBERSHIP was on. Lists the pairs and changes nothing unless APPLY=true, so the
# owner reviews the list first: a missing pair can be an owner's deliberate removal.
#
#   bundle exec rake comvor:ops:backfill_inbox_members ACCOUNT_ID=12
#   bundle exec rake comvor:ops:backfill_inbox_members ACCOUNT_ID=12 APPLY=true
#   bundle exec rake comvor:ops:backfill_inbox_members ACCOUNT_ID=12 APPLY=true SKIP=34:7,35:7   (inbox:user pairs left out)

namespace :comvor do
  namespace :ops do
    desc 'List (APPLY=true: add) account users missing from the inboxes of ACCOUNT_ID'
    task backfill_inbox_members: :environment do
      account = Account.find(ENV.fetch('ACCOUNT_ID'))
      apply = ActiveModel::Type::Boolean.new.cast(ENV.fetch('APPLY', false))
      skip = ENV.fetch('SKIP', '').split(',').map(&:strip).reject(&:empty?)
      pairs = InboxMember.missing_account_pairs(account).reject { |inbox, user_id| skip.include?("#{inbox.id}:#{user_id}") }

      pairs.each { |inbox, user_id| puts "account=#{account.id} inbox=#{inbox.id} (#{inbox.name}) user=#{user_id}" }
      puts "#{pairs.size} missing pair(s)#{apply ? ', adding' : ', nothing changed (APPLY=true to add)'}"
      next unless apply

      pairs.group_by(&:first).each { |inbox, rows| inbox.add_members(rows.map(&:last)) }
    end
  end
end
