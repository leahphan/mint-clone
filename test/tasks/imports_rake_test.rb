require "test_helper"
require "rake"

class ImportsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.none?
    Rake::Task["imports:purge_pending"].reenable
  end

  test "purge_pending deletes pending imports older than a day, with their uploaded CSV" do
    expired = create(:import, :pending, created_at: 25.hours.ago)
    recent = create(:import, :pending, created_at: 1.hour.ago)
    completed = create(:import, created_at: 1.week.ago)

    assert_output(/Deleted 1 expired pending imports/) { Rake::Task["imports:purge_pending"].invoke }

    assert_not Import.exists?(expired.id)
    assert Import.exists?(recent.id)
    assert Import.exists?(completed.id)
  end
end
