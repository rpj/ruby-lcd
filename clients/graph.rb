#!/usr/bin/ruby
# A crappy graph client for LCDProc
# Written just as a test, but could be adapted for more
# interesting things (XMMS visualizations?)
#
# $Id: graph.rb,v 1.4 2003/08/16 09:51:29 rjoseph Exp $

require 'lcd'

DURATION    = 20
COL_START   = 3
COL_END     = 18

lcd = LCD.new("Graph")
lcd.proc_resp = true

scr = LCD::Screen.new("Graph", "graph", "off", (DURATION * 8))
high_mark = LCD::Text.new("5", 1, 1)
low_mark = LCD::Text.new("0", 1, 4)
scr.add_widgets(high_mark, low_mark)

bars = []
COL_START.upto(COL_END) do |i|
   bars[i - COL_START] = LCD::Bar.new(0, "v", i, 4)
end

scr.add_widgets(*bars)
lcd.trap_sigint()
lcd.connect()
lcd.add_screen(scr)

i, up = 1, true
while (true)
   COL_START.upto(COL_END) do |j|
      bars[j-3].len = i % 40
      up = (i > 38 ? (up ? false : true) : (i < 1 ? true : up))
      i = (up ? i + 1 : i - 1)
   end

   lcd.update_screen(scr)
   sleep(0.1)
end
