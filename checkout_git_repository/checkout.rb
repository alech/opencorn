#!/usr/bin/env ruby

require 'rubygems'
require 'git'
require 'pp'
require 'fileutils'
require 'opencorn/config'

DEBUG = false

# This script is supposed to be run regularly.
#
# It clones the 'official' git repository and figures
# out which is the latest tag that contains 2 or more
# signatures from board members.
#
# It then resets the checked out git repository to this state
# and clones it to its final place.

def valid_signature(tag)
	system "git-verify-tag #{tag}"
end

def signer_id(tag)
	result = `git-verify-tag #{tag} 2>&1`
	result[/key ID ([0-9A-F]{8})/, 1]
end

if OpenCorn::Config['GNUPGHOME'] then
	ENV['GNUPGHOME'] = OpenCorn::Config['GNUPGHOME']
end

tmpdir = Dir.mktmpdir
# check out in tmpdir
g = Git.clone(OpenCorn::Config['ACCEPTED_REPO'], tmpdir)

object_signatures = {}
most_current_signed_object = nil
pp g.tags if DEBUG
# iterate over all tags, as they are not sorted by time
g.tags.each do |tag|
	puts "Checking tag #{tag.name}" if DEBUG
	if ! tag.name[/^[a-zA-Z0-9]+$/] then
		STDERR.puts 'Argh, non-alphanumeric tag name, WTF?'
		next
	end
	object_id = tag.contents_array[0][/object ([a-f0-9]+)/, 1]
	puts "Refers to object id #{object_id}" if DEBUG
	if valid_signature(tag.name) then
		puts "Valid signature on #{tag.name} by #{signer_id(tag.name)}" if DEBUG
		object_signatures[object_id] ||= {}
		object_signatures[object_id][signer_id(tag.name)] = 1
	end
end
pp object_signatures if DEBUG

# iterate over all commits to find the first that has more than one signature
g.log.each do |log|
	if object_signatures[log.objectish] && object_signatures[log.objectish].keys.size >= 2 then
		most_current_signed_object = log.objectish
		break
	end
end

if ! most_current_signed_object then
	STDERR.puts "Sorry, no object with more than one signed tag found."
	exit 1
end

g.reset_hard(most_current_signed_object)

begin
FileUtils.rm_r OpenCorn::Config['ACCEPTED_SIGNED_REPO'], :secure => true
rescue # ignore errors deleting the directory
end
Git.clone(tmpdir, OpenCorn::Config['ACCEPTED_SIGNED_REPO'], :depth => 1)
