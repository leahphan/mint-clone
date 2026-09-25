# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A personal finance web app inspired by Mint.com. Rails 8.1 monolith on PostgreSQL, Hotwire (Turbo + Stimulus) with importmap and Tailwind — no Node build step.

## Principles

- Conventional Rails architecture; prefer standard Rails features over custom abstractions.
- Keep implementations simple.
- Keep models to associations, validations, and small queries. Put multi-step operations (e.g. CSV import) in plain service objects in `app/services/` with a `.call(...)` class method, tested in `test/services/`.
- Don't add gems without a clear reason.
- Don't modify unrelated code.
- Write tests for meaningful behavior, and run the relevant tests after making changes.
- Use FactoryBot factories (`test/factories/`) for test data, not YAML fixtures. Each test creates the records it needs with `create`/`build`.
- Stay on Minitest (not RSpec). Stub sparingly with `minitest-mock` (`object.stub(:method, value) { ... }`), only at boundaries a test can't easily control, such as time, the network, or race windows. Prefer real records over mocking our own models.
- Keep explanations concise.
- The user is the primary Git author. Commit as them and include Claude as a `Co-Authored-By:` trailer.

## Frontend

- Rails ERB + Hotwire (Turbo, Stimulus) + Tailwind CSS v4 via `tailwindcss-rails`. No React, no Node build.
- Visual reference: Mint.com circa Nov 2017 (white top bar, DM Sans with light body/heavy headings, green `#00c96d`, blue `#30c0e3`, orange `#fd8a10` CTAs, white cards on `#f4f4f4`). Use our own wordmark (`config.x.app_name`), never Intuit/Mint logos or artwork.
- Reuse before adding:
  - Colors and fonts are tokens in `@theme` in `app/assets/tailwind/application.css` (`bg-mint-green`, `text-mint-muted`, …); no raw hex values in views.
  - Repeated primitives are component classes in the same file: `btn` + `btn-primary`/`btn-secondary`, `btn-link`, `card`/`card-header`/`card-title`, `form-label`/`form-input`/`form-hint`, `data-table`, `status-dot`. Everything else is utility classes in the markup.
  - Shared markup is partials in `app/views/shared/` (`navbar`, `hero`, `flash`, `page_header`, `card` via `render layout:`, `form_errors`, `empty_state`); formatting goes in `ApplicationHelper` (`amount_tag`, `short_date`, `nav_link`, `status_dot`).
- Account balances shown in the UI are placeholders (`placeholder_balance`) until real balances are built.

## Environment

Ruby 4.0.3 via rbenv. Run commands from the project root — the parent directory pins an old Ruby. Local PostgreSQL databases: `mint_development`, `mint_test`.

## Commands

```bash
bin/dev                                      # dev server + Tailwind watcher (foreman, Procfile.dev)
bin/rails db:migrate                         # commit db/schema.rb with the migration
bin/rails test                               # all tests (Minitest)
bin/rails test test/models/foo_test.rb:42    # single file or test
bin/rails test:system                        # system tests (not included in bin/rails test)
bin/rubocop                                  # lint (rubocop-rails-omakase); -a to autocorrect
bin/ci                                       # full local CI (see config/ci.rb)
```
