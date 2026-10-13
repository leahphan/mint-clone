import { Controller } from "@hotwired/stimulus"

// Reloads the Turbo Frame around this element every few seconds while the element is in it, e.g.
// while new transactions are being categorized, leaving the rest of the page, like a flash message,
// as it is. The frame is rendered without a src (a frame can't load a page that gives it a src
// pointing at itself), so the first poll sets one and replaces the frame's content; later polls
// reload it, which morphs in place (refresh="morph"). Once a poll no longer has this element, it stops.
// Give the frame's other top-level elements ids, so the morph still matches them when this one goes.
export default class extends Controller {
  static values = { interval: { type: Number, default: 3000 } }

  connect() {
    this.frame = this.element.closest("turbo-frame")
    this.keepContent = this.keepContent.bind(this)
    this.frame?.addEventListener("turbo:frame-missing", this.keepContent)
    this.timer = setInterval(() => this.reload(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    this.frame?.removeEventListener("turbo:frame-missing", this.keepContent)
  }

  // Skips a tick while the last reload is still loading, so a slow response isn't cancelled.
  reload() {
    if (!this.frame || document.hidden || this.frame.hasAttribute("busy")) return

    if (this.frame.src) this.frame.reload()
    else this.frame.src = window.location.href
  }

  // The response had no frame: an error page (try again next tick, keeping what's shown) or the
  // sign-in page because the session ended (go there).
  keepContent(event) {
    event.preventDefault()
    if (event.detail.response.redirected) event.detail.visit(event.detail.response)
  }
}
