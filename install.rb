#!/usr/bin/ruby
# Install file for the Ruby-LCD library
# (C) 2003, Ryan Joseph <j@seph.us>
# $Id: install.rb,v 1.2 2003/08/16 09:51:29 rjoseph Exp $

require 'rbconfig'
require 'ftools'
include Config

lib_file    = 'lcd.rb'
clients     = ['xmms.rb', 'fortune.rb', 'imap.rb', 'graph.rb']
client_dir  = './clients'
lib_dir     = './lib'

if (ARGV[0] == "clean")
   puts "Cleaning installation..."
   puts "Removing #{CONFIG['rubylibdir']}/#{lib_file}"
   File::delete("#{CONFIG['rubylibdir']}/#{lib_file}")

   puts "Removing files from #{CONFIG['bindir']}"
   clients.each() { |f|
      puts "\tRemoving #{CONFIG['bindir']}/#{f}"
      File::delete("#{CONFIG['bindir']}/#{f}")
   }
else
   puts "Installing #{lib_file} to #{CONFIG['rubylibdir']}"
   File::install("#{lib_dir}/#{lib_file}",
   "#{CONFIG['rubylibdir']}/#{lib_file}", 0644)

   puts "Installing contents of #{client_dir} to #{CONFIG['bindir']}"
   clients.each() { |f|
      puts "\t#{f} -> #{CONFIG['bindir']}/#{f}"
      File::install("#{client_dir}/#{f}", "#{CONFIG['bindir']}/#{f}", 0755)
   }
end

puts "\nDone.\n"
