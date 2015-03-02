#!/usr/bin/env ruby
# encoding=utf-8
# This scripts will provide the functionality to change password
# of multiple e-mail accounts along with the option to remove all
# e-mails from one e-mail / domain from the queue
executable_name = File.basename($PROGRAM_NAME)

# Configure script values
HOST_NAME = 'localhost'
HASH_FILE_PATH = '/root/.accesshash'
LOG_FILE_PATH = '/var/log/mail_tool.log'
SPAM_LOG_FILE_PATH = '/var/log/mailtool_spam.log'
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
      false
    else
      true
    end
  end

  #  Method to get username
  def cpanel_username
    @username = `/scripts/whoowns #{domain}`.chomp
    username
  end

  # Method to check e-mail account existense
  def check_email_existense
    @email_account_without_domain = normalized_email.split('@').first
    @home = `grep ^#{username} /etc/passwd | cut -d \: -f6`.chomp
    @email_account_search = `grep -w #{@email_account_without_domain} #{@home}/etc/#{domain}/passwd 2>/dev/null`
    if @email_account_search.empty?
      puts "E-mail account #{normalized_email} doesn't exist"
    else
      true
    end
  end

  # Method to Print account details
  def print_details
    puts '=================: User-details: ============'
    puts "Email-address: #{email}"
    puts "Domain name: #{domain}"
    puts "Domain owner: #{username}"
    @trueuser = `grep -w \^#{username} /etc/trueuserowners|cut -d\: -f2|uniq`.chomp
    puts 'True owner: ' + `grep -w #{@trueuser}$ /etc/trueuserdomains|uniq` if @trueuser != 'root'
    puts ''
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
    @password = SecureRandom.urlsafe_base64(12)
    process_options = { domain: @domain, email: @email, password: @password }
    passwd_result = cp_email.change_password(process_options)
    if passwd_result[:params][:data][0][:reason] == ''
      puts ''
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
    @valid_domain = options[:valid_domain]
    @search_direction = options[:direction]
    case @search_direction
    when 'From'
      @direction = '-f'
    when 'To'
      @direction = '-r'
    else
      @direction = '-f'
    end
  end

  # Get mail count from the queue
  def count
    @mailcount = `exiqgrep -c #{@direction} #{@email} 2>/dev/null`.chomp
  end

  # Method to clear mailqueue
  def log
    @comment_text = '=====Spam log for the account ' + "#{@email}" + '====='
    time = Time.new
    logtime = time.strftime('%Y-%m-%d %H:%M')
    @mail_exim_id = `exiqgrep -i -R #{@direction} #{@email} | tail -1`
    @full_mail_body = `exim -Mvc #{@mail_exim_id} 2>/dev/null`
    @mail_log = `exim -Mvl #{@mail_exim_id} 2>/dev/null`
    File.open("#{SPAM_LOG_FILE_PATH}", 'a') do |spam_logfile|
      spam_logfile.puts "#{logtime}: #{@email}"
      spam_logfile.puts "#{@comment_text}"
      spam_logfile.puts "Email count: #{@emailcount}"
      spam_logfile.puts ''
      spam_logfile.puts "#{@full_mail_body}"
      spam_logfile.puts ''
      spam_logfile.puts "#{@mail_log}"
      spam_logfile.puts ''
    end
  end

  # Clear mailque based on search
  def clear_queue
    case @remove
    when 'one'
      puts "Clearing e-mails #{@search_direction} #{@email}"
      puts ''
      `exiqgrep -i #{@direction} #{@email} | xargs -P10 -i exim -Mrm '{}' > /dev/null`
    when 'all'
      if @valid_domain
        puts "Removing all e-mails #{@search_direction} #{@domain}"
        `exiqgrep -i #{@direction} #{@domain} | xargs -P10 -i exim -Mrm '{}' > /dev/null`
      else
        puts "#{@domain} is not a valid local domain. Removing e-mails #{@search_direction} #{@email} instead"
        `exiqgrep -i #{@direction} #{@email} | xargs -P10 -i exim -Mrm '{}' > /dev/null`
      end
    else
      puts "Didn't remove any emails from the mailque"
    end
  end

  # Print messages based on mailque count
  def message
    case @remove
    when 'one'
      puts "There are no emails #{@search_direction} #{@email} found in the queue"
    when 'all'
      puts "There are no emails #{@search_direction} #{@domain} found in the queue"
    end
  end
end

# Getting command line arguments using optparse
require 'optparse'
options = { email: nil, change: false, remove: false, domain: nil, info: false, help: false, valid_domain: false, direction: 'From' }
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage\: #{executable_name} \[-options] \<emailaddress\(s\)\>"
  opts.separator 'Options'
  opts.separator '-c [--changepassword ] -r [ --remove] -a  [ --removeall] -i [--info ] -d [ --direction] <emailaddress(s)>'
  opts.separator '-h or --help : Displays this Help'
  opts.separator ''
  opts.on('-c', '--changepassword', 'Changes password of given e-mail account(s)') { options[:change] = true }
  opts.on('-r', '--remove', 'Remove all mails from the account(s)') { options[:remove] = 'one' }
  opts.on('-a', '--removeall', 'Remove all mails from the domain(s)') { options[:remove] = 'all' }
  opts.on('-i', '--info', 'Prints account information') { options[:info] = true }
  opts.on('-d', '--direction', 'It toggles the direction of mailque search From -> To') { options[:direction] = 'To' }
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
  puts "#{option_parser}"
  exit
else
  ARGV.each do|email_address|
    email = Email.new(email_address)
    options[:email] = email.normalize
    options[:domain] = email.domain_info
    options[:valid_domain] = email.check_valid_domain
    if email.email_validate && options[:valid_domain]
      options[:username] = email.cpanel_username
      if email.check_email_existense == true
        if options[:change]
          change_email_password = ChangeEmailPassword.new(options)
          change_email_password.change_password
        end
        email.print_details if options[:info]
      end
    elsif options[:valid_domain] == false
      puts "Domain #{options[:domain]} doesn\'t exist"
    end
    if options[:remove]
      queue = MailQueue.new(options)
      if queue.count.to_i > 1
        queue.log
        queue.clear_queue
      else
        queue.message
      end
    end
    puts '------------------------------------------'
  end
end
