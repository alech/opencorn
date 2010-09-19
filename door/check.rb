#!/usr/bin/env ruby

require 'pp'
require 'digest/sha1'
require 'rubygems'
require 'git'

DEBUG = false

# query keys 
keys = []
keys_result = `pkcs15-tool --list-keys -w`
keys_result.split(/\n\n/).each do |key|
    pp key if DEBUG
    key.split(/\n/).each do |line|
        if line[/Usage/] && ! line[/sign/] then
            next # not used for signing, skip
        end
        # FIXME
        # those access flags are just educated guesses for
        # now, research that they mean what I think they do
        if line[/Access Flags/] && \
            (! line[/alwaysSensitive/] || ! line[/neverExtract/] \
             || ! line[/local/]) then
             next # access flags are weird, skip
        end
        if key_id = line[/ID          : ([0-9a-f]+)/, 1] then
            keys << key_id
        end
    end
end

# get DER-encoded public keys
keys_der = keys.map do |k|
    `pkcs15-tool --read-public-key #{k} | openssl rsa -inform pem -outform der -pubin`
end

# compute git hash on the keys
key_hashes = keys_der.map do |k|
     Digest::SHA1.hexdigest('blob ' + k.size.to_s + "\0" + k)
end
pp key_hashes if DEBUG

# check if one of the keys is present in the git repository
REPO = '/home/alech/devel/opencorn/testing/accepted_signed'
g = Git.open(REPO)

key_in_repo = nil
key_hashes.each_with_index do |hash, index|
    # find blobs in HEAD that have the correct git hash
    if g.object('HEAD').gtree.blobs.to_a.find { |entry| entry[1].objectish == hash } then
        key_in_repo = keys[index]
        break
    end
end

if ! key_in_repo then
    # FIXME: log attempt
    STDERR.puts "Sorry, no usable keys found on card."
    exit 1
end

puts key_in_repo if DEBUG
