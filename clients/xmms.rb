#!/usr/bin/ruby
# A really nice XMMS info display client for LCDProc
# 
# Requires the Info Pipe plugin is installed and activated
# (should be bundled with all recent XMMS installs)
#
# (C) 2003 Ryan Joseph, <J@seph.us>
# Released under the GNU GPL, www.gnu.org
# $Id: xmms.rb,v 1.5 2003/08/17 21:39:14 rjoseph Exp $

require 'lcd'

DAEMONIZE      = true               # fork into background 
INFO_PIPE      = '/tmp/xmms-info'   # the info pipe file
CHAR_WIDTH     = 5                  # width of one char on display
DURATION       = 8                  # secs to stay on display

if (DAEMONIZE && cpid = fork())
   puts "Child process id: #{cpid}"
   exit!
end

lcd   = LCD.new("XMMS")
scr   = LCD::Screen.new("XMMS.s0", "XMMS", "normal", (DURATION * 8))
ttl   = LCD::Title.new("0:00/0:00")
sname = LCD::Scroller.new("(C) 2003 Ryan Joseph", 1, 2, 20, 3, "h", 5)
tstat = LCD::Text.new("Stopped", 4, 3)
tmode = LCD::Text.new("<>", 1, 3)
tkbps = LCD::Text.new("000 kbps", 13, 3)
tnum  = LCD::Text.new("000/000", 13, 4)
bar   = LCD::Bar.new(0, "h", 2, 4)
tline = LCD::Text.new("--------", 2, 4)
bar_w = (CHAR_WIDTH * 10).to_f()

scr.add_widgets(ttl, sname, tstat, tkbps, bar, tmode, tnum, tline)
scr.add_widgets(LCD::Text.new("<", 1, 4), LCD::Text.new(">", 10, 4))

lcd.trap_sigint()
lcd.proc_resp = true
lcd.connect()
lcd.add_screen(scr)

begin
   stat  = Regexp::compile(/Status:\s+(.*)/)
   pos   = Regexp::compile(/Position:\s+(\d\d?):(\d\d)/)
   time  = Regexp::compile(/Time:\s+(\d\d?):(\d\d)/)
   bps   = Regexp::compile(/Current\s+bitrate:\s+(\d+)/)
   name  = Regexp::compile(/Title:\s+(.*)/)
   tunes = Regexp::compile(/Tunes\s+in\s+playlist:\s+(\d+)/)
   curr  = Regexp::compile(/Currently\s+playing:\s+(\d+)/)

   tpos, ttime_secs, tpos_cnt, last_time, pl_num, mcnt =
    "", 0, 0, "", 0, 0, 0
   while (true)
      file = File.new(INFO_PIPE)
      
      file.readlines().each() { |line|
         if (stat =~ line)
            s = $1
            tstat.text = s

            if (s =~ /Playing/)
               if ((mcnt % 4) == 0)
                  tmode.text = ".."
               elsif ((mcnt % 4) == 1)
                  tmode.text = ">."
               elsif ((mcnt % 4) == 2)
                  tmode.text = ">>"
               else
                  tmode.text = ".>"
               end

               tline.text = ""
            elsif (s =~ /Paused/)
               tmode.text = ((mcnt.to_i() % 2) == 0) ? "//" : "--"
            elsif (s =~ /Stopped/)
               tmode.text = "<>"
               bar.len = 0
               tline.text = "--------"
            end
         elsif (pos =~ line)
            tpos = "#{$1}:#{$2}"
            tpos_cnt += 1
            
            if ((tpos_cnt % 3) == 0)
               pos_tsecs = (($1.to_i() * 60) + $2.to_i()).to_f()
               if (pos_tsecs > 0)
                  tline.text = ""
                  bar.len = ((pos_tsecs / ttime_secs) * bar_w).to_i()
               end
            end
         elsif (time =~ line)
            now = "#{$1}:#{$2}"
            
            unless (now == last_time)
               ttime_secs = (($1.to_i() * 60) + $2.to_i()).to_f()
            end
            
            ttl.text = "#{tpos}/#{now}"
            last_time = now
         elsif (bps =~ line)
            tkbps.text = ($1.to_i() / 1000).to_s() + " kbps"
         elsif (name =~ line)
            a = $1
            sname.text = "#{a}" unless (sname.text =~ /#{a}/)
         elsif (tunes =~ line)
            n = $1.to_i()
            pl_num = n unless (n == pl_num)
         elsif (curr =~ line)
            c = $1.to_i()
            unless (tnum.text =~ %r!#{c}/#{pl_num}!)
               tnum.text = "#{c}/#{pl_num}"
            end
         end
      }           

      lcd.update_screen(scr)
      mcnt += 1 
      file.close()
      sleep(1)
   end
rescue
   # most likely xmms-info doesn't exist, just try a bunch of times
   sleep(1)
   retry
ensure
   file.close()
end
