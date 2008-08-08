# Client library for LCDProc
# (C) 2003, Ryan Joseph <j@seph.us>
# Released under the GNU GPL, www.gnu.org
# $Id: lcd.rb,v 1.15 2003/08/18 02:46:21 rjoseph Exp $

require 'socket'

module Debug
   @@debug_on = false
   
   def debug(str)
      if (@@debug_on)
         STDERR.printf(">> " + str + "\n")
      end
   end

   def debug_on=(val); @@debug_on = val; end
end

class InvalidLCDCommandError < StandardError; end

class LCD
# Inner classes
   class Screen
      include Debug

      attr_accessor(:sid, :name, :width, :height, :has_changed)
      attr_reader(:widget_list)

      def initialize(sid, name = "rblcdscreen", hbeat = "normal",
        dur = -1, pri = 128, w = -1, h = -1)
         @has_changed = String.new()

         @sid, @name, @pri, @duration, @width, @height, @heartbeat =
          sid, name, pri, dur, w, h, chk_hbeat(hbeat)
         @widget_list = []
      end

      def to_s; "Screen #{@sid} is #{@name}"; end

      def heartbeat=(val)
         @heartbeat = chk_hbeat(val) 
         unless (@has_changed =~ /-heartbeat/)
            @has_changed.concat("-heartbeat #{val} ")
         end
      end
      
      def duration=(d)
         @duration = d
         unless (@has_changed =~ /-duration/)
            @has_changed.concat("-duration #{d} ")
         end
      end
      
      def pri=(p)
         @pri = p
         debug("Changing priority to #{p}!")
         unless (@has_changed =~ /-priority/)
            @has_changed.concat("-priority #{p} ")
         end
      end

      def pri_up; self.pri = @pri / 2; end
      def pri_down; self.pri = @pri * 2; end

      def make_set_str()
         "screen_set {#{@sid}}" +
          " -priority #{@pri}" +
          " -name {#{@name}}" +
          (@duration > 0 ? " -duration #{@duration}" : "") +
          (@width > 0 ? " -width #{@widt}" : "") +
          (@height > 0 ? " -height #{@height}" : "") +
          " -heartbeat #{@heartbeat}"
      end

      def add_widget(wid)
         return nil unless (wid.kind_of?(LCD::Widget))

         debug("add_widget(" + wid.to_s() + ")")
         @widget_list.push(wid)
      end

      def add_widgets(*wids)
         wids.each() { |w| add_widget(w) }
      end

      def get_wid_ndx(wid)
         return nil unless @widget_list.member?(wid)
         "#{@sid}_" + @widget_list.index(wid).to_s
      end
      
      protected
      def chk_hbeat(h)
         unless (h =~ /on|heart|normal|default|off|none|slash/i)
            raise InvalidLCDCommandError,
             "Invalid heartbeat option: #{h}"
         end

         return h
      end
   end   # LCD::Screen

   class Status
      attr_reader(:listen, :menu, :ignore, :error)
      def initialize(l = nil, m = nil, i = nil, e = nil)
         @listen, @menu, @ignore, @error  = l, m, i, e
      end

      def to_s; "#{@listen}:#{@menu}:#{@ignore}:#{@error}"; end
   end

   # Don't ever create this class directly
   class Widget
      attr_reader(:type)
      attr_accessor(:has_changed)
      def initialize(type)
         @type, @set_has_changed = chk_type(type), nil
      end

      protected
      def chk_type(t)
         unless (t =~ /string|hbar|vbar|title|icon|scroller|frame/i)
            raise InvalidLCDCommandError, "Invalid widget type #{t}"
         end

         return t
      end
   end   # LCD::Widget

   class Text < Widget
      attr_reader(:text)
      def initialize(text, x = 1, y = 1)
         super("string")

         @text, @x, @y = text, x, y
         @text.tr!("{}", "[]")
      end

      def to_s; "#{@x} #{@y} {#{@text}}"; end
      def text=(t); @text = t; @has_changed = true; end
      def change_pos(x, y); @x, @y = x, y; @has_changed = true; end
   end   # LCD::Text

   class Title < Widget
      attr_reader(:text)
      def initialize(text)
         super("title")
         @text = text
         @text.tr!("{}", "[]")
      end

      def to_s; "{#{@text}}"; end
      def text=(t); @text = t; @has_changed = true; end
   end   # LCD::Title

   class Bar < Widget
      attr_reader(:len)
      def initialize(len, orien = "h", x = 1, y = 1)
         @len, @x, @y = len, x, y

         if (orien =~ /^([hv]).*/i)
            @orien = $1.downcase()
         else raise InvalidLCDCommandError,
          "Bad bar orientation '#{orien}'"
         end

         super(@orien + "bar")
      end

      def to_s; "#{@x} #{@y} #{@len}"; end
      def len=(l); @len = l; @has_changed = true; end
      def incr_len; @len += 1; @has_changed = true; end
      def decr_len; @len -= 1; @has_changed = true; end
      def change_pos(x, y); @x, @y = x, y; @has_changed = true; end
   end   # LCD::Bar

   class Scroller < Widget
      attr_reader(:text)
      def initialize(text, l, t, r, b, d = "h", s = 1)
         @text, @left, @top, @right, @bottom, @speed =
          text, l, t, r, b, s

         if (d =~ /^([hv]).*/i)
            @direction = $1.downcase()
         else raise InvalidLCDCommandError,
          "Invalid scroller direction '#{d}'"
         end

         @text.tr!("{}", "[]")
         super("scroller")
      end

      def to_s
         "#{@left} #{@top} #{@right} #{@bottom} "+
          "#{@direction} #{@speed} {#{@text}}"
      end

      def text=(t); @text = t; @has_changed = true; end
      def speed=(s); @speed = s; @has_changed = true; end
      
      def flip_direction
         @direction = @direction == "h" ? "v" : "h"
         @has_changed = true
      end
      
      def change_pos(l, t, r, b)
         @left, @top, @right, @bottom = l, t, r, b
         @has_changed = true
      end
   end   # LCD::Scroller

# Start of LCD class code
   include Debug

   attr_reader(:screen_list)
   attr_accessor(:proc_resp)
   protected
   SOCK_NEWLINE = "\x0D\x0A"
   VERSION = '$Id: lcd.rb,v 1.15 2003/08/18 02:46:21 rjoseph Exp $'

   def initialize(name = 'rblcdproc', server = 'localhost', port = '13666')
      @server, @port, @name, @screen_list, @proc_resp =
       server, port, name, {}, false
   end

   public
   def to_s
      "lcdd://#{@name}@#{@server}:#{@port}/ version #{VERSION}"
   end

   def connect
      @socket = TCPSocket.open(@server, @port)
      debug(@socket.peeraddr().to_s())
      
      wts("hello")
      wts("client_set -name '#{@name}'")
   end

   def add_screen(scr)
      return nil unless (scr.instance_of?(LCD::Screen))
      
      wts("screen_add '#{scr.sid}'")
      ret = wts(scr.make_set_str())

      @screen_list[scr.sid] = scr
      scr.widget_list.each() { |w|
         debug("Screen #{scr.sid} has widget: " + w.to_s())
         wndx = scr.get_wid_ndx(w)
            
         wts("widget_add {#{scr.sid}} {#{wndx}} " + w.type)
         ret = wts("widget_set {#{scr.sid}} {#{wndx}} " + w.to_s())
      }

      return ret
   end

   def update_screen(scr)
      return nil unless (scr.is_a?(String) || scr.is_a?(LCD::Screen))
      scr = scr.is_a?(String) ? @screen_list[scr] : scr

      ret = nil
      debug("in update_screen(#{scr.sid})") 
      scr.widget_list.each() { |w|
         if (w.has_changed)
            ret = wts("widget_set {#{scr.sid}} {" + scr.get_wid_ndx(w) +
             "} " + w.to_s())
         end

         w.has_changed = false
      }

      if (scr.has_changed != "")
         ret = wts("screen_set {#{scr.sid}} #{scr.has_changed}")
         scr.has_changed = ""
      end

      return ret
   end

   def del_screen(scr)
      id = scr.is_a?(String) ? scr : scr.sid

      scr.widget_list.delete_if() { |w|
       wts("widget_del #{id} " + scr.get_wid_ndx(w))
      }

      debug("Screen #{id} has " + scr.widget_list.size().to_s() +
       " widgets left after deletion")
      
      ret = wts("screen_del {#{id}}")
      @screen_list.delete(id)
      return ret
   end

   def get_status 
      @socket.readline(); chomp!
      debug(" <- " + $_)

      if ($_ =~ /^huh\?\s+(.*)/)
         stat = Status.new(nil, nil, nil, $1)
      elsif ($_ =~ /^listen\s+(.*)/)
         stat = Status.new($1)
      elsif ($_ =~ /^ignore\s+(.*)/)
         stat = Status.new(nil, nil, $1)
      else
         stat = Status.new()
      end

      return stat
   end

   def [](key)
      return nil unless key.is_a?(String)
      return @screen_list[key]
   end

   def send_raw(str); wts(str); end

   def close
      @screen_list.delete_if() { |k, v| del_screen(v) }
      @socket.shutdown()
   end

   def trap_sigint; trap("INT", proc { close(); exit(); }); end

   private
   def wts(str)
      debug(" -> '#{str}'")
      raise "Socket has not yet been established" if (@socket.nil?) 
      @socket.write(str + SOCK_NEWLINE)

      stat = nil
      if (@proc_resp)
         stat = get_status()
         raise(InvalidLCDCommandError, stat.error) if (stat.error)
      end

      return stat
   end
end

=begin
= Ruby-LCD Documentation
=== (C) 2003 Ryan Joseph, http://seph.us/
This document has all of the API documentation for the Ruby-LCD library, found
in (({lib/lcd.rc})) in the distrobution of Ruby-LCD, available from 
((<URL:http://seph.us/?z=code-ruby-lcd>))

For CVS reference, the last revision of this file: (({$Id: lcd.rb,v 1.15 2003/08/18 02:46:21 rjoseph Exp $}))

Errors, corrections, comments: ((<URL:mailto:j@seph.us>))

= Class Documentation
== Index
* ((<LCD>))
* ((<LCD::Screen>))
* ((<LCD::Widget>))
* ((<LCD::Bar>))
* ((<LCD::Scroller>))
* ((<LCD::Text>))
* ((<LCD::Title>))
* ((<LCD::Status>))

== Code Examples
For many great, wonderful, amazing examples, see the (({clients/})) directory
in the distro files, or just check the CVS repository.  I would put a quick
bit of inline code here, but lets just say that RubyDoc ((*sucks*)), so that
won't be happening.  Sorry.

= LCD
The main class for communicating with LCDProc, it requires that objects
descended from type (({LCD::Widget})) are added to it in order to create
display objects on the device.

Throughout this documentation, when describing method signatures, required
arugments will be given without any decoration - such as (({Foo.bar(baz)})) -
whereas optional arguments will be given in the Ruby style, enclosed in square
brackets with the default value given as an assignment - such as
(({Foo.boo([baz="hi!"])})).

== Class Methods

--- LCD.new([name = 'rblcdproc'], [server = 'localhost'], [port = 13666])
Creates a new instance of (({LCD})), using the supplied arguments if given to
connect to an instance of LCDProc.  However ((*note*)) that no actual socket
connection is made until ((<LCD#connect>)) is called!

== Instance Attributes
=== Read-only
*  (({screen_list})) - As hash (keyed by screen ID) of all the ((<LCD::Screen>))s
   currently registered with this (({LCD})) object.

=== Read/write
*  (({proc_resp (defaults to false)})) - If set to (({true})), causes (({LCD})) to
   automatically grab each server response after sending a request.  This is
   usually what you probably want, so I would suggest turning this on.  An 
   ((<LCD::Status>)) object will be returned by methods that glean a server 
   response, provided this is set.  Otherwise, you'll need to use 
   ((<LCD#get_status>)) to continually get server responses.  ((*Note:*)) See
   ((<LCD::Status>)) for more information on server responses, because
   ((<LCD#get_status>)) can be dangerous!
*  (({debug_on (defaults to false)})) - Inherited from the (({Debug})) class,
   turns on debugging output.

== Instance Methods
Let me just lodge my official complaint against the Ruby standard practice of
using '#' to notate instance methods: although I use it here for
standardization purposes, I think it may be one of the ugliest and most
annoying features of the language.  Ok, I'm done now ;)

--- LCD#add_screen(LCD::Screen)
Adds a (({LCD:Screen})) to this (({LCD})).  If the screen has any
widgets registered, these will be added to the server and displayed.
Otherwise, it will be necessary to add the widgets with
((<LCD::Screen#add_widget>)) or ((<LCD::Screen#add_widgets>)) and then call
((<LCD#update_screen>)).

--- LCD#connect()
Create a connection to the LCDProc server supplied as arguments to
(({.new()})) earlier.  

--- LCD#close()
Closes the connection to the server, calling ((<LCD#del_screen>)) as necessary
to ensure that each screen is correctly deleted from the server.

--- LCD#del_screen(LCD::String)
--- LCD#del_screen(String)
Deletes a screen from the display and from the internal (({screen_list})).

--- LCD#get_status()
Gets the last server response and returns an ((<LCD::Status>)) object
describing that response.

--- LCD#send_raw(String)
Send a raw command to the LCDProc server.  Not recommended for use.

--- LCD#trap_sigint()
Setups a SIGINT trap: (({trap("INT", proc { close(); exit(); });}))
This is the recommended way to get out of the infinte "main loop" in a client
program, as it cleans up correctly.

--- LCD#update_screen(LCD::Screen)
--- LCD#update_screen(String)
If called with a (({String})) argument, will look up the screen using that
name from the (({screen_list})).  Updates the given screen on the display,
updating any widgets that have changed first and then updating the screen
itself, if it has changed.  Safe to call from the main program loop every
time, it will only send data if elements have actually changed.

--- LCD#[](String)
Overloaded bracket operators to allow easy access to (({screen_list})).
Returns an ((<LCD::Screen>)) object corresponding to key given, or (({nil}))
if the object is not in the (({screen_list})).

= LCD::Screen
An object that allows you to define a "screen" in the LCDProc space.  A
"screen" is just a container that will have ((*n*)) "widgets" (any object
descended from ((<LCD::Widget>))) that are the actual display objects on the
screen.

== Class Methods
--- LCD::Screen.new(sid, [name = "rblcdscreen"], [hbeat = "normal"], [dur = -1], [pri = 128], [w = -1], [h = -1])
Creates a new (({LCD::Screen})).  The only required argument is (({sid})), the
screen ID.  This can be anything as long as no other screen or widget shares
it: my common practice is to use the name of the program and a unique screen
ID, such as "IMAP.s0" for the IMAP client.

The duration, width, and height ((({dur})), (({w})), and (({h}))) - if set to
-1 as they are by default - will inherit the standard settings for the
display currently in use.  This is the recommended behavior.

Duration is given as the number of "frames," of which there are 8 in a second.

Priority ((({pri}))) is a power of 2: see (({man LCDd})) on your system for
more information, but in general, a lower power of 2 indicates a higher
priority.  If you want your screen to be given focus ASAP, the suggested
method is to set the priority to 64 for a set period of time, and then lower
it back to 128 after you are satisfied.

== Instance Attributes
=== Read-only
*  (({widget_list})) - A hash (key by widget ID) of ((<LCD::Widget>))s in this screen.

=== Read/write
*  (({duration (Integer)})) - The number of frames (8/sec) for this screen to remain on
   the display.
*  (({name (String)})) - The screen name
*  (({has_changed (Boolean)})) - Boolean indicating if this screen has changed or not.
*  (({heartbeat (String)})) - A proper hearbeat string
   ((({on|heart|normal|default|off|none|slash}))).
*  (({height (Integer)})) - Screen height
*  (({pri (Integer)})) - The priority of this screen, as a power of 2, with
   128 being the default ('normal') priority.  For a detailed explanation of
   of screen priority works, see (({man LCDd})) on your system.
*  (({sid (String)})) - The screen ID
*  (({width (Integer)})) - Screen width

== Instance Methods
--- LCD::Screen#add_widget(LCD::Widget)
Add a single ((<LCD::Widget>)) to this screen

--- LCD::Screen#add_widgets(*LCD::Widget)
Add a variable amount of ((<LCD::Widget>))s to this screen

--- LCD::Screen#get_wid_ndx(LCD::Widget)
Get the index of the widget in (({widget_list})), if it exists, (({nil})) if
not.

--- LCD::Screen#pri_up()
Move this screen's priority up one level (subtract a power of two)

--- LCD::Screen#pri_down()
Move this screen's priority down one level (add a power of two)

--- LCD::Screen#to_s()
Return a string representation of this (({LCD::Screen})).  Not very useful,
seriously.

= LCD::Widget
(({LCD::Widget})) would be an abstract class in Ruby, if Ruby had abstract
classes.  (({LCD::Widget})) is just that: abstract.  You'll never instantiate
and (({LCD::Widget})), although I suppose you could.  But you'll never want
to, seriously, believe me on this one.  And if you did, well, you have more
problems than just wanting to instantiate an (({LCD::Widget})), and I suggest
you seek personal help.

However, never fear.  This class is actually quite useful, and its use
highlights one of the great reasons why OOP is ... so great.  Of course, that
reason being none of the methods that deal with widget-ish type objects ever
really need to know what widget-ish type object they're actually dealing with.
They're perfectly content to play around with (({LCD::Widget}))s all day and
never know that they're actually playing with an ((<LCD::Bar>)), or maybe an
((<LCD::Scroller>)) (or even some crazy widget type that doesn't even exist
yet because I haven't written it)!

And that, my friends, is the beauty of (({LCD::Widget})).  Wow.

== Known Subclasses
* ((<LCD::Bar>))
* ((<LCD::Scroller>))
* ((<LCD::Text>))
* ((<LCD::Title>))

== Class Methods
--- LCD::Widget.new(type)
Uhm, didn't I just tell you never to make one of these?  Then why are you
still reading this!

== Instance Attributes
Any class derived from (({LCD::Widget})) will automatically have these

=== Read-only
*  (({type})) - The type of (({LCD::Widget}))

=== Read/write
*  (({has_changed})) - Boolean indicating if this widget has changed: is used
   to know when to update display elements on the LCD.

== Instance Methods
None

= LCD::Bar
A bar graph-type UI element, can be either vertical or horizontal depending on
how the object is constructed.

== Class Methods
--- LCD::Bar.new(len, [orien = "h"], [x = 1], [y = 1])
Constructs a new (({LCD::Bar})) widget object.  (({len})) is required and is
the length of the bar, in pixels.  The defaults will create a horizontal bar
at coordinates (1, 1) - the top left-hand corner.

To create a vertical bar, simply set the second arugment ((({orien}))) to "v".

== Instance Attributes
=== Read/write
*  (({len})) - The length of the bar.  Change this and then call
   ((<LCD#update_screen>)) on the screen that owns this widget to change the
   length of this bar.

== Instance Methods
--- LCD::Bar#change_pos(x, y)
Move the bar to (({(x, y)}))

--- LCD::Bar#decr_len()
Decrease bar length by one.

--- LCD::Bar#incr_len()
Increase bar length by one.

= LCD::Scroller
A text UI object that can contain text data of any length, and will scroll to
ensure that all of the data is displayed on the screen.

== Class Methods
--- LCD::Scroller.new(text, left, top, right, bottom, [direction = "h"], [speed = 1])
Create a new (({LCD::Scroller})) object, initialized with (({text})), starting
at coordinates (({(left, top)})) and extending to (({(right, bottom)})).

A horizontal scroller will scroll data to the left and right of the screen,
and a vertical scroller will scroll up and down.

If speed is positive, it indicates how many frames per each movement of the
scroller.  If it is negative, it indicates how many movements the scroller
should make in one frame (of which there are 8/sec by default).

== Instance Attributes
=== Read/write
*  (({text})) - The text of this (({Scroller})), a (({String}))
*  (({speed})) - The speed of this (({Scroller}))

== Instance Methods
--- LCD::Scroller#change_pos(left, top, right, bottom)
Change the position of the scroller as described in ((<LCD::Scroller.new>))

= LCD::Text
A text UI element, about as generic as it gets.

== Class Methods
--- LCD::Text.new(text, x, y)
Create a new (({LCD::Text})) object at (({(x, y)})) with text (({text}))

== Instance Attributes
=== Read/write
*  (({text})) - The text of this (({Scroller})), a (({String}))

== Instance Methods
--- LCD::Text#change_pos(x, y)
Move the text object to (({(x, y)}))

= LCD::Title
A UI element that describes the LCDProc title widget: it will be placed on the
first line (the "heartbeat" line) and if it is larger than the space alloted
by LCDProc, will be scrolled to fit.

== Class Methods
--- LCD::Title.new(text)
Create a new title with text (({text}))

== Instance Attributes
=== Read/write
*  (({text})) - The text of this (({Scroller})), a (({String}))

== Instance Methods
None

= LCD::Status
The (({LCD::Status})) object is returned by most methods in the ((<LCD>))
class, most namely ((<LCD#get_status>)).  It is an encapsulation of the status
of the (({LCD})) object in relation to the server: it's basically a single
server response.

You use these objects by examining their instance attributes (look a ways down
the page).

Most of the time, you can just toss these away without worrying about them:
that's mainly what the (({proc_resp})) variable is for in the (({LCD})) class.
By this I mean that most of the errors you'll get from LCDProc are errors
involving not creating a widget/screen correctly, and it's easy enough to look
at the display and see that you screwed something up.

However, they may be times you actually want to know what the server said.
There are two ways you can do this:
*  Assuming you set (({proc_resp})) in for your (({LCD})) object, just grab
   the return of any of the (({LCD})) instance methods that talk to the server
   (FYI, they are: ((<LCD#connect>)), ((<LCD#update_screen>)),
   ((<LCD#add_screen>)), and ((<LCD#del_screen>))).  This return value will be
   an object of type (({LCD::Status})), which you can then poke an prod to you
   little heart's content.
*  If you ((*haven't*)) set (({proc_resp})), the (({LCD})) class won't grab
   any response from the server, leaving them all to get queued up.  You can
   use the ((<LCD#get_status>)) function as many times as you need, but ((*be
   ware!*))  ((<LCD#get_status>)) is ((*blocking*)), so if you are waiting for
   it to return, you may end up waiting forever, which - needless to say - can
   get pretty annoying pretty quickly.

Therefore, the recommended way to deal with status messages is to set
(({proc_resp})) and then just take a look at them when you need to and toss
the rest.

== Class Methods
--- LCD::Status.new([l = nil], [m = nil], [i = nil], [e = nil])
Now lets be serious, when are you ((*ever*)) going to need to make one of
these!  Seriously, don't, they're not for you!

== Instance Attributes
Here be the meat'n'potatoes of the (({LCD::Status})) object.  Each of these
attributes servers two purposes: first, whichever one is non-(({nil}))
indicates the actual state of the connection.  Secondly, the value of that
non-(({nil})) element will be a string with important information relating to
that state (for example, if the non-(({nil})) element is the (({listen}))
attribute, then it will be set with the ID of the screen to be listening to).
Without further ado:

*  (({listen})) - The server has notified us to listen to this screen.
*  (({menu})) - The server has sent us a menu event (((*not yet
   implemented*)))
*  (({ignore})) - The server has told us to ignore this screen.
*  (({error})) - The server has responded with an error message (most likely a
   "huh?" message.)

== Instance Methods
None, examine instance attributes for useful information.

=end
