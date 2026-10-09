# Default categories for every user (see Category::DEFAULTS). Idempotent: run it any time with
# bin/rails db:seed. Categories a user already has (matched by name, ignoring case) are left as
# they are. A fresh database has no users; bin/rails users:set_password creates one with these.
User.find_each(&:add_default_categories)
