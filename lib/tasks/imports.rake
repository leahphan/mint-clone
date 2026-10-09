namespace :imports do
  desc "Delete pending imports (and their uploaded CSV) that weren't confirmed within 24 hours"
  task purge_pending: :environment do
    puts "Deleted #{Import.purge_expired} expired pending imports."
  end
end
