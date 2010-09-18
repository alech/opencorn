#!/usr/bin/env ruby

require 'rubygems'
require 'git'
require 'pp'
require 'fileutils'

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

ENV['GNUPGHOME'] = '/tmp' # FIXME: dir from config with board member keyring
SOURCE_REPOSITORY = '/home/alech/devel/opencorn/testing/accepted'
DEST_REPOSITORY = '/home/alech/devel/opencorn/testing/accepted_signed'

tmpdir = Dir.mktmpdir
# check out in tmpdir
g = Git.clone(SOURCE_REPOSITORY, tmpdir)

object_signatures = {}
most_current_signed_object = nil
g.tags.each do |tag|
    if ! tag.name[/^[a-zA-Z0-9]+$/] then
        puts 'Argh, non-alphanumeric tag name, WTF?'
        exit 1
    end
    object_id = tag.contents_array[0][/object ([a-f0-9]+)/, 1]
    if valid_signature(tag.name) then
        object_signatures[object_id] ||= {}
        object_signatures[object_id][signer_id(tag.name)] = 1
        if object_signatures[object_id].keys.length >= 2 then
            most_current_signed_object = object_id
            break
        end
    end
end

pp object_signatures if DEBUG

if ! most_current_signed_object then
    STDERR.puts "Sorry, no object with more than one signed tag found."
    exit 1
end

g.reset_hard(most_current_signed_object)

begin
FileUtils.rm_r DEST_REPOSITORY, :secure => true
rescue # ignore errors deleting the directory
end
g2 = Git.clone(tmpdir, DEST_REPOSITORY)
