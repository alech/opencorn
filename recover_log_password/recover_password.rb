#!/usr/bin/env ruby

require 'rubygems'
require 'opencorn/config'
require 'secretsharing'

k = OpenCorn::Config['SECRETSHARING_K']
s = SecretSharing::Shamir.new(k)

(1..k).each do |i|
	puts "Please enter share number #{i}:"
	s << STDIN.readline.chomp
	print "\e[H\e[2J"
end

puts "The password is: #{s.secret_password}"
