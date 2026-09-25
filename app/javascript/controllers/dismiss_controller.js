import { Controller } from "@hotwired/stimulus"

// Removes its element, e.g. a flash message's close button.
export default class extends Controller {
  close() {
    this.element.remove()
  }
}
