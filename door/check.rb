#!/usr/bin/env ruby

require 'pp'
require 'digest/sha1'
require 'tempfile'
require 'rubygems'
require 'git'
require 'openssl'

DEBUG = true

# query keys 
keys = []
key_lengths = []
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
        if line[/ModLength/] then
            if (! line[/1024/] || !line[/2048/]) then
                next # unsupported key length
            else
                key_lengths << line[/(\d+)/, 1]
            end
        end
        if key_id = line[/ID          : ([0-9a-f]+)/, 1] then
            keys << key_id

        end
    end
end

pp key_lengths if DEBUG

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
# FIXME: REPO URI from config
REPO = '/home/alech/devel/opencorn/testing/accepted_signed'
g = Git.open(REPO)

key_in_repo = nil
key_file    = nil
key_length  = nil
key_hash    = nil
key_hashes.each_with_index do |hash, index|
    # find blobs in HEAD that have the correct git hash
    if blob = g.object('HEAD').gtree.blobs.to_a.find { |entry| entry[1].objectish == hash } then
        key_file    = blob[0]
        key_in_repo = keys[index]
        key_length  = key_lengths[index]
        key_hash    = key_hashes[index]
        break
    end
end

if ! key_in_repo then
    # FIXME: log attempt
    STDERR.puts "Sorry, no usable keys found on card."
    exit 1
end

puts key_in_repo if DEBUG

# FIXME: REVO_REPO from config
REVO_REPO = '/home/alech/devel/opencorn/testing/revocation'
g_r = Git.open(REVO_REPO)
if g_r.object('HEAD').gtree.blobs.to_a.find { |entry| entry[1].objectish == key_hash } then
    STDERR.puts "Sorry, key has been revoked."
    exit 2
end

# let the user sign a challenge
challenge = 'OpenCorn' + ("%011d" % Time.now.to_i) + OpenSSL::Random.random_bytes(13)
signer_file = Tempfile.new 'tbs'
signer_file.print challenge
signer_file.close

signature_file = Tempfile.new 'sig'
puts "pkcs15-crypt -k #{key_in_repo} -s -i #{signer_file.path} -o #{signature_file.path} --pkcs1 --sha-256" if DEBUG
system "pkcs15-crypt -k #{key_in_repo} -s -i #{signer_file.path} -o #{signature_file.path} --pkcs1 --sha-256"

# verify signature
sig_result = `openssl rsautl -verify -in #{signature_file.path} -inkey #{REPO}/#{key_file} -keyform DER -pubin -raw`[-32,32]
if ! $?.success? then
    # FIXME: log
    STDERR.puts "Invalid signature, sorry"
    exit 3
end

if sig_result != challenge then
    # FIXME: log
    STDERR.puts "Signature does not match challenge."
    exit 4
end

# TODO: call command to open door
puts "Open Sesame!"
