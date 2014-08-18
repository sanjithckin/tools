#!/usr/bin/env ruby
# encoding=utf-8
# This scripts will provide the functionalty to change password
# of multiple e-mail accounts along with the option to remove all
# e-mails from one e-mail / domain from the queue
executable_name = File.basename($PROGRAM_NAME)
require 'optparse'
options = { email: nil, change: false, remove: false, domain: nil, log: false }
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{executable_name} [Options]"
  opts.separator ''
  opts.separator 'Options'
  opts.separator '-c or --changepassword: Changes password of e-mail account'
  opts.separator '-r or --remove: Removes e-mails from given e-mail account'
  opts.separator '-a or --removeall: Removes all e-mails from particlar domain'
  opts.separator '-h or --help : Displays this Help'

  opts.on('-c', '--changepassword', 'Enter email account') { options[:change] = true }
  opts.on('-r', '--remove', 'Remove all mails from the account') { options[:remove] = 'one' }
  opts.on('-a', '--removeall', 'Remove all mails from the domain') { options[:remove] = 'all' }
  opts.on('-h', '--help', 'Displays Help') { puts option_parser }
end
option_parser.parse!
# Following class will take arguments from optparse and process it
class EmailToggle
  # Configure below values
  HOST_NAME = 'localhost'
  HASH_FILE_PATH = '/root/.accesshash'
  LOG_FILE_PATH = '/root/direct_login_spam.log'
  # Configuration ends
  require 'securerandom' ## Used to Generate password
  require 'lumberg'  ## Used to interact with C-panel api
  def initialize(options)
    @email = options[:email]
    @remove = options[:remove]
    @domain = options[:domain]
  end

  def change_email_password
    server = Lumberg::Whm::Server.new(
              host: HOST_NAME,
              hash: `cat #{HASH_FILE_PATH}`
              )
    username = `/scripts/whoowns #{@domain}`.chomp
    cp_email = Lumberg::Cpanel::Email.new(
                server:       server,  # An instance of Lumberg::Server
                api_username: username  # User whose cPanel we'll be interacting with
                )
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
      puts "#{passwd_result[:params][:data][0][:reason]}"
    end
  end
  
  def clear_queue
    puts "#{@remove}"
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

# Following block will retrive e-mail address from command line.
# If they pass the validation it will pass to the E-mail toggle class.
if ARGV.empty?
  puts "#{option_parser}"
else
  ARGV.each do|emailadd|
    if emailadd.include? '@'
      options[:email] = emailadd.downcase
      options[:domain] = emailadd.split('@').last.downcase
      dom_check = `grep ^#{options[:domain]} /etc/userdomains`
      if dom_check.empty?
        puts 'Given domain doesn\'t exist'
      else
        mailtoggle = EmailToggle.new(options)
        mailtoggle.change_email_password if options[:change]
        mailtoggle.clear_queue if options[:remove]
      end
    else
      puts 'Invalid Email address entered'
    end
  end
end


