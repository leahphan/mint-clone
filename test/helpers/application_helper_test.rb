require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "amount_tag colours positive, negative and zero amounts" do
    assert_dom_equal %(<span class="text-mint-green font-semibold tabular-nums whitespace-nowrap">$2,500.00</span>), amount_tag(BigDecimal("2500"))
    assert_dom_equal %(<span class="text-mint-negative font-semibold tabular-nums whitespace-nowrap">-$54.32</span>), amount_tag(BigDecimal("-54.32"))
    assert_includes amount_tag(BigDecimal("0")), "text-mint-ink"
  end

  test "short_date omits the year only for the current year" do
    travel_to Date.new(2026, 9, 25) do
      assert_equal "Sep 1", short_date(Date.new(2026, 9, 1))
      assert_equal "Dec 31, 2025", short_date(Date.new(2025, 12, 31))
    end
  end

  test "nav_link marks the active link" do
    active = nav_link("Overview", "/accounts", active: true)
    assert_includes active, "border-mint-green"
    assert_includes active, %(aria-current="page")

    assert_not_includes nav_link("Categories", "/categories", active: false), "aria-current"
  end
end
