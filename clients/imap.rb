#!/usr/bin/ruby
# IMAP mail client for LCDProc
#
# Written mainly for 20x4 displays, but wouldn't require much
# modification to be adapted to other display sizes
#
# You can give your login information on the command line, ie:
# ./imap.rb hostname username password
# but remember that if there are other users on your machine
# they can see your information with a simple 'ps' command
#
# Kill this program with SIGINT (kill -INT pid) to have it
# cleanup correctly and exit gracefully
#
# (C) 2003 Ryan Joseph <j@seph.us>
# Released under the GNU GPL, www.gnu.org
# $Id: imap.rb,v 1.6 2003/08/16 19:38:05 rjoseph Exp $

require 'net/imap'
require 'lcd'

# Change these
HOSTNAME    = ARGV[0] || ''   # mail host
USER        = ARGV[1] || ''   # user name
PASSWORD    = ARGV[2] || ''   # password
FOLDER      = 'INBOX'   # mail folder to check
PORT        = 143       # IMAP port
CHECK_TIME  = 3         # interval between checks, in minutes
DURATION    = 4         # seconds on the screen
ALERT_TIME  = 15        # for new mail, how many secs at high priority
DAEMONIZE   = true      # fork into background when run 

# Don't change anything beyond here
if (HOSTNAME == '' || USER == '' || PASSWORD == '')
   puts "Usage: #{$0} [server] [username] [password]"
   puts "Or define these in the file #{$0}"
   exit!
end

raise "ALERT_TIME must be greater than 5" unless (ALERT_TIME > 5)
if (DAEMONIZE && cpid = fork())
   puts "Child process ID: #{cpid}"
   exit()
end

lcd = LCD.new("IMAP")
scr = LCD::Screen.new("IMAP.s0", "IMAP", "normal", (DURATION * 8))
scr.add_widget(LCD::Title.new("imap://" + HOSTNAME))

t1 = LCD::Text.new("Checking...", 1, 2)
t2 = LCD::Text.new("(C) 2003 Ryan Joseph", 1, 3)
t3 = LCD::Text.new("ryanj -at- seph.us", 1, 4)
scr.add_widgets(t1, t2, t3)

lcd.trap_sigint()
lcd.proc_resp = true
lcd.connect()
lcd.add_screen(scr)

sec_cnt, last_unseen, priup_cnt, main_cnt = ((CHECK_TIME * 60) + 1), 0, 0, 0
begin
   imap = Net::IMAP.new(HOSTNAME, PORT)
   imap.login(USER, PASSWORD)

   while (true)
      if (sec_cnt > (CHECK_TIME * 60))
         t1.text = "Checking..."
         lcd.update_screen(scr)
         
         ret = imap.status(FOLDER, ["MESSAGES", "UNSEEN"])
         t1.text = "Folder:    " + FOLDER 
         t2.text = "Messages:  " + ret['MESSAGES'].to_s()
         t3.text = "Unseen:    " +
          (ret['UNSEEN'] == 0 ? "None" : ret['UNSEEN'].to_s())

         if (priup_cnt == 0 && ret['UNSEEN'] > 0)# - last_unseen > 0))
            t1.text = "  *** New mail ***" 
            scr.pri_up()
            priup_cnt += 1
         end
         
         lcd.update_screen(scr)

         sec_cnt = 1
         last_unseen = ret['UNSEEN']
      end

      sec_cnt += 1
      priup_cnt += 1 if priup_cnt > 0

      if (priup_cnt > ALERT_TIME)
         scr.pri_down()
         priup_cnt = 0
         lcd.update_screen(scr)
      elsif (priup_cnt == 5)
         t1.text = "Folder:    " + FOLDER
         lcd.update_screen(scr)
      end
      
      imap.noop() if ((main_cnt % 60) == 0)
      main_cnt += 1
      sleep(1)
   end
rescue
   puts $!.message
   puts $!.backtrace
   puts "Retrying..."
   retry
ensure
   imap.disconnect()
end
