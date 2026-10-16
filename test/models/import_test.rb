require "test_helper"

class ImportTest < ActiveSupport::TestCase
  test "the uploaded CSV of a pending import never reaches the SQL log or inspect output" do
    log = StringIO.new
    previous = ActiveRecord::Base.logger
    ActiveRecord::Base.logger = ActiveSupport::Logger.new(log)

    import = create(:import, :pending, content: "2026-09-28,PAYMENT - THANK YOU,,1000.00,977.35\n")

    assert_includes log.string, %(INSERT INTO "imports")
    assert_not_includes log.string, "PAYMENT - THANK YOU"
    assert_not_includes import.inspect, "PAYMENT - THANK YOU"
  ensure
    ActiveRecord::Base.logger = previous
  end

  test "pending imports expire after a day" do
    assert create(:import, :pending, created_at: 25.hours.ago).expired?
    assert_not create(:import, :pending, created_at: 23.hours.ago).expired?
    assert_not create(:import, created_at: 1.week.ago).expired?
  end

  test "an import is categorizing until its job finishes, or for at most CATEGORIZING_TIMEOUT" do
    running = create(:import, categorizing_since: 1.minute.ago)
    stuck = create(:import, categorizing_since: (Import::CATEGORIZING_TIMEOUT + 1.minute).ago)
    done = create(:import)

    assert_equal [ running ], Import.categorizing.to_a
    assert_not_includes Import.categorizing, stuck
    assert_not_includes Import.categorizing, done
  end
end
