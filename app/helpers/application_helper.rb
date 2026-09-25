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
  def amount_tag(amount)
    color = if amount.positive? then "text-mint-green"
    elsif amount.negative? then "text-mint-negative"
    else "text-mint-ink"
    end

    tag.span number_to_currency(amount), class: "#{color} font-semibold tabular-nums whitespace-nowrap"
  end

  # "Sep 1" this year, "Sep 1, 2025" otherwise.
  def short_date(date)
    date.strftime(date.year == Date.current.year ? "%b %-d" : "%b %-d, %Y")
  end
end
