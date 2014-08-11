#!/usr/bin/env ruby
=begin
This scripts will provide the funstionalty to change password of multiple e-mail account using c-panel api.
It can also remove all e-mails from one account / domain from the queue
=end
executable_name = File.basename($PROGRAM_NAME)
require 'optparse'
options = { email: nil, change: false, remove: nil, domain: nil, log: false }
option_parser = OptionParser.new do |opts|
  opts.banner = "Usage: #{executable_name} [Options]"
  opts.separator  ""
  opts.separator  "Options"
  opts.separator  "-c or --changepassword: Changes password of an e-mail account"
  opts.separator  "-r or --remove: Removes e-mails from particular e-mail account"
  opts.separator  "-a or --removeall: Removes all e-mails from particlar domain"
  opts.separator  "-h or --help : Displays this Help"

  opts.on('-c', '--changepassword', 'Enter the email account to change password') { |change| options[:change] = true }
  opts.on( '-r', '--remove','Remove all mails from the address') { |remove| options[:remove] = 'one' }
  opts.on( '-a', '--removeall','Remove all mails from the domain' ) { |removeall| options[:remove] = 'all'}
  opts.on('-h', '--help', 'Displays Help') { puts option_parser}
end
option_parser.parse!

class EmailToggle
######## Configure below values #######  
  @@hostname = 'localhost'
  @@hash_path = '/root/.accesshash'
  @@log_path = '/root/direct_login_spam.log'
######## Configuration ends ###########
  require 'securerandom'
  require 'lumberg'  
  def initialize(options)
    @email = options[:email]
    @remove = options[:remove]
    @domain = options[:domain]
    @change = options[:change]
  end
  def process_options
    if @change
      server = Lumberg::Whm::Server.new(
      host: @@hostname,
      hash: %x(cat #{@@hash_path})
      )
    username = %x(/scripts/whoowns #{@domain}).chomp
    puts "#{username}"
    cp_email = Lumberg::Cpanel::Email.new(
      server:       server,  # An instance of Lumberg::Server
      api_username: username  # User whose cPanel we'll be interacting with
      )
      puts "Changing password of #{@email} using lumberg"
      @password = SecureRandom.urlsafe_base64(12)
      process_options = { domain: @domain, email: @email, password: @password }
      puts "process_options : #{process_options}"
      passwd_result = cp_email.change_password( process_options )
        if passwd_result[:params][:data][0][:reason] == ''
           puts "Successfully changed password of #{@email}"
           time = Time.new
           logtime = time.strftime("%Y-%m-%d %H:%M")
           File.open("#{@@log_path}", "a"){ |somefile| somefile.puts "#{logtime} : #{@email} "}
        else
           puts "#{passwd_result[:params][:data][0][:reason]}"
           exit
        end
    end
    case @remove
    when 'one'
      puts "Clearing e-mails under #{@email}"
      %x( exiqgrep -i -f #{@email} | xargs -P10 -i exim -Mrm '{}' | tail -1 )
    when 'all'
      puts "Removing all e-mails under #{@domain}"
        %x( exiqgrep -i -f #{@domain} | xargs -P10 -i exim -Mrm '{}' | tail -1 )
        %x( /etc/init.d/exim restart )
    else
      puts "Didn't remove any emails from the mailque"
    end
  end
end

ARGV.each do|emailadd|
if emailadd.include? "@"
  options[:email] = emailadd.downcase
  puts "Email: #{options[:email]}"
  options[:domain] = emailadd.split("@").last.downcase
  puts "Domain: #{options[:domain]}"
  dom_check = %x( grep ^#{options[:domain]} /etc/userdomains )
  if dom_check.empty?
    puts "Given domain doesn't exist"
  else
    mailtoggle = EmailToggle.new(options)
    mailtoggle.process_options
  end
else
  puts"Invalid Email address entered";
end
end
if ARGV.empty?
  puts "#{option_parser}"
end
