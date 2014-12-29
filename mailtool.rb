#!/usr/bin/env ruby
# encoding=utf-8
# This scripts will provide the functionality to change password
# of multiple e-mail accounts along with the option to remove all
# e-mails from one e-mail / domain from the queue
executable_name = File.basename($PROGRAM_NAME)

# Configure script values
HOST_NAME = 'localhost'
HASH_FILE_PATH = '/root/.accesshash'
LOG_FILE_PATH = '/root/direct_login_spam.log'
# Configuration finished

# Class to validate and normalize e-mail address and get domain name / username.
class Email
  attr_reader :email, :normalized_email, :domain, :username
  def initialize(email)
    @email = email
  end

  # Method to normalize e-mail address
  def normalize
    @normalized_email = email.downcase
    normalized_email
  end

  # Method to validate e-mail address
  def email_validate
    if !normalized_email.include? '@'
      puts "Invalid e-mail address entered #{normalized_email}"
    else
      true
    end
  end

  #  Method to get domain info from e-mail
  def domain_info
    @domain = normalized_email.split('@').last
    domain
  end

  # Check domain existence
  def check_valid_domain
    @dom_check = `grep ^#{domain} /etc/userdomains`
    if @dom_check.empty?
      puts "The domain #{domain} doesn\'t exist"
    else
      true
    end
  end

  #  Method to get username
  def cpanel_username
    @username = `/scripts/whoowns #{domain}`.chomp
    username
  end

  # Method to Print mail details
  def print_details
    puts "Email-address: #{email}"
    puts "Domain name: #{domain}"
    puts "Domain owner: #{username}"
    @trueuser = `grep -w \^#{username} /etc/trueuserowners|cut -d\: -f2|uniq`.chomp
    puts 'True owner: ' + `grep -w #{@trueuser}$ /etc/trueuserdomains|uniq` if @trueuser != 'root'
  end
end

# Class take email address from optparse/ ARGV and change password
class ChangeEmailPassword
  require 'securerandom' ## Used to Generate password
  require 'lumberg'  ## Used to interact with C-panel api

  def initialize(options)
    @email = options[:email]
    @remove = options[:remove]
    @domain = options[:domain]
    @username = options[:username]
  end

  # Method to change e-mail account password
  def change_password
    # https://github.com/site5/lumberg
    server = Lumberg::Whm::Server.new(host: HOST_NAME, hash: `cat #{HASH_FILE_PATH}`)
    cp_email = Lumberg::Cpanel::Email.new(server: server, api_username: @username)
    puts "Changing password of #{@email} using lumberg"
    @password = SecureRandom.urlsafe_base64(12)
    process_options = { domain: @domain, email: @email, password: @password }
    passwd_result = cp_email.change_password(process_options)
    if passwd_result[:params][:data][0][:reason] == ''
      puts "Successfully changed password of #{@email}"
      time = Time.new
      logtime = time.strftime('%Y-%m-%d %H:%M')
      File.open("#{LOG_FILE_PATH}", 'a') { |logfile| logfile.puts "#{logtime}: #{@email}" }
    else
      # Print c-panel error message if failed to change the password
      puts "#{passwd_result[:params][:data][0][:reason]}"
    end
  end
end

# Class to clear mailqueue
class MailQueue
  def initialize(options)
    @email = options[:email]
    @remove = options[:remove]
    @domain = options[:domain]
  end

  # Method to clear mailqueue
  def clear_queue
    case @remove
    when 'one'
      puts "Clearing e-mails under #{@email}"
      `exiqgrep -i -f #{@email} | xargs -P10 -i exim -Mrm '{}' | tail -1`
    when 'all'
      puts "Removing all e-mails under #{@domain}"
      `exiqgrep -i -f #{@domain} | xargs -P10 -i exim -Mrm '{}' | tail -1`
    else
      puts "Didn't remove any emails from the mailque"
    end
  end
end

# Getting command line arguments using optparse
require 'optparse'
options = { email: nil, change: false, remove: false, domain: nil, info: false, help: false }
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{executable_name} [Options]"
  opts.separator ''
  opts.separator 'Options'
  opts.separator '-c or --changepassword: Changes password of e-mail account'
  opts.separator '-r or --remove: Removes e-mails from given e-mail account'
  opts.separator '-a or --removeall: Removes all e-mails from particular domain'
  opts.separator '-i or --info : Displays domain information'
  opts.separator '-h or --help : Displays this Help'

  opts.on('-c', '--changepassword', 'Enter email account') { options[:change] = true }
  opts.on('-r', '--remove', 'Remove all mails from the account') { options[:remove] = 'one' }
  opts.on('-a', '--removeall', 'Remove all mails from the domain') { options[:remove] = 'all' }
  opts.on('-i', '--info', 'Enter email account') { options[:info] = true }
  opts.on('-h', '--help', 'Displays Help') do
    options[:help] = true
    puts option_parser
  end
end
option_parser.parse!

# Following block will retrieve e-mail address from command line.
# We are using ARGV to retrieve multiple e-mail address
# If they pass the validation it will pass to the corresponding classes.
if ARGV.empty? && options[:help] == false
  puts 'Please enter some options and e-mail address'
  puts "#{option_parser}"
  exit
else
  ARGV.each do|email_address|
    email = Email.new(email_address)
    options[:email] = email.normalize
    options[:domain] = email.domain_info
    if email.email_validate && email.check_valid_domain && options[:change]
      options[:username] = email.cpanel_username
      change_email_password = ChangeEmailPassword.new(options)
      change_email_password.change_password
      email.print_details if options[:info]
    end
    if options[:remove]
      queue = MailQueue.new(options)
      queue.clear_queue
    end
  end
end
