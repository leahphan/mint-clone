namespace :users do
  desc "Create a user (with the default categories) or change a user's password: bin/rails users:set_password EMAIL=you@example.com"
  task set_password: :environment do
    require "io/console"

    email = ENV["EMAIL"].to_s.strip
    abort "Usage: bin/rails users:set_password EMAIL=you@example.com" if email.empty?

    password = $stdin.getpass("Password for #{email}: ")
    abort "The password can't be blank." if password.blank?
    abort "The passwords don't match." unless $stdin.getpass("Confirm password: ") == password

    user = User.find_or_initialize_by(email_address: email)
    created = user.new_record?
    User.transaction do
      user.update!(password: password)
      created ? user.add_default_categories : user.sessions.destroy_all
    end

    puts created ? "Created #{user.email_address} with the default categories." : "Changed the password for #{user.email_address} and signed it out everywhere."
  rescue ActiveRecord::RecordInvalid => error
    abort error.record.errors.full_messages.to_sentence
  end
end
