module ApplicationHelper
  def app_name
    Rails.application.config.x.app_name
  end

  # A top-bar link, underlined in green when it's the current section.
  def nav_link(label, path, active: current_page?(path))
    classes = "inline-flex h-full items-center border-b-2 px-1 text-xs font-bold tracking-wide uppercase transition-colors"
    classes += active ? " border-mint-green text-mint-ink" : " border-transparent text-mint-muted hover:text-mint-ink"

    link_to label, path, class: classes, aria: { current: ("page" if active) }
  end

  # A currency amount, green when positive and red when negative.
  # size: :hero is the large, light-weight number style used for headline totals.
  def amount_tag(amount, size: :default)
    color = if amount.positive? then "text-mint-green"
    elsif amount.negative? then "text-mint-negative"
    else "text-mint-ink"
    end
    size_classes = size == :hero ? "text-4xl font-light tracking-tight" : "font-semibold"

    tag.span number_to_currency(amount), class: "#{color} #{size_classes} tabular-nums whitespace-nowrap"
  end

  def status_dot(amount)
    tag.span class: "status-dot #{amount.negative? ? "bg-mint-negative" : "bg-mint-green"}", aria: { hidden: true }
  end

  # "Sep 1" this year, "Sep 1, 2025" otherwise.
  def short_date(date)
    date.strftime(date.year == Date.current.year ? "%b %-d" : "%b %-d, %Y")
  end

  # TODO: Replace with the real account balance once balances are implemented.
  # A stable made-up number per account, so the design can be reviewed with realistic values.
  def placeholder_balance(account)
    cents = Random.new(account.id).rand(1_000..1_500_000)
    balance = BigDecimal(cents) / 100
    account.credit_card? ? -balance : balance
  end
end
