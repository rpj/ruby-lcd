#!/usr/bin/ruby
# A client that displays a fortune from the famous fortune program
# Not very cool, but neat for testing and eye candy ;)
#
# (C) 2003 Ryan Joseph, <J@seph.us>
# Released under the GNU GPL, www.gnu.org
# $Id: fortune.rb,v 1.5 2003/08/16 09:51:29 rjoseph Exp $

require 'lcd'

WAIT_TIME = 12

def get_fortune
   text = `fortune`
   text.split("\n").join(" / ").gsub(/\s+/, " ")
end

lcd = LCD.new("Fortune")
lcd.proc_resp = true
scr = LCD::Screen.new("fs0", "fortune.rb", "slash", (WAIT_TIME * 8))

title = LCD::Title.new("Fortune!")
scroll = LCD::Scroller.new(get_fortune(), 1, 2, 20, 4, "v", 30)
scr.add_widgets(title, scroll)

lcd.trap_sigint()
lcd.connect()
lcd.add_screen(scr)

begin
   while (true)
      sleep(WAIT_TIME)

      scroll.text = get_fortune()
      lcd.update_screen(scr)

      stat = lcd.get_status()
      puts "Got an error: #{stat.error}" if (stat.error)
   end
rescue
   puts "Aieee: " + $!.message
   puts $!.backtrace
end

lcd.close()
