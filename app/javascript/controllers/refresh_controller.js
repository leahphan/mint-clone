import { Controller } from "@hotwired/stimulus"

// Reloads the Turbo Frame around this element every few seconds while the element is in it, e.g.
// while new transactions are being categorized. The frame morphs in place (refresh="morph"), so
// the rest of the page, like a flash message, stays put; once a reload no longer has this element,
// the polling stops.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.timer = setInterval(() => this.reload(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (document.hidden || !frame) return

    // The frame starts without a src (it was rendered with the page), so the first reload sets one.
    if (frame.src) frame.reload()
    else frame.src = window.location.href
  }
}
