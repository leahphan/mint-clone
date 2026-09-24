# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

A personal finance web app inspired by Mint.com. Rails 8.1 monolith on PostgreSQL, Hotwire (Turbo + Stimulus) with importmap — no Node build step.

## Principles

- Conventional Rails architecture; prefer standard Rails features over custom abstractions.
- Keep implementations simple.
- Don't add gems without a clear reason.
- Don't modify unrelated code.
- Write tests for meaningful behavior, and run the relevant tests after making changes.
- Use FactoryBot factories (`test/factories/`) for test data, not YAML fixtures. Each test creates the records it needs with `create`/`build`.
- Keep explanations concise.
- The user is the primary Git author. Commit as them and include Claude as a `Co-Authored-By:` trailer.

## Environment

Ruby 4.0.3 via rbenv. Run commands from the project root — the parent directory pins an old Ruby. Local PostgreSQL databases: `mint_development`, `mint_test`.

## Commands

```bash
bin/dev                                      # dev server
bin/rails db:migrate                         # commit db/schema.rb with the migration
bin/rails test                               # all tests (Minitest)
bin/rails test test/models/foo_test.rb:42    # single file or test
bin/rails test:system                        # system tests (not included in bin/rails test)
bin/rubocop                                  # lint (rubocop-rails-omakase); -a to autocorrect
bin/ci                                       # full local CI (see config/ci.rb)
```
