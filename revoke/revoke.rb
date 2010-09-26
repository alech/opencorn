#!/usr/bin/env ruby

require 'openssl'
require 'base64'
require 'ftools'
require 'opencorn/config'
require 'rubygems'
require 'hashcash'
require 'git'

# This is supposed to be run as a login shell for a user, possibly with an
# empty password for self-revocation.


def read_and_check_hashcash(resource, required_bits)
	stamp = STDIN.readline.chomp
	s = begin
			HashCash::Stamp.new(:stamp => stamp)
		rescue
			nil
		end
	if ! s then
		STDERR.puts "Sorry, could not load stamp."
		exit 1
	end
	begin
		s.verify(resource, required_bits)
	rescue => ex
		STDERR.puts "Sorry, invalid stamp: #{ex.message}"
		exit 2
	end
end

resource = "opencorn-" + Base64.encode64(OpenSSL::Random.random_bytes(9)). \
                         chomp.downcase
required_bits = OpenCorn::Config['HASHCASH_BITS'] || 24

# TODO: JavaScript implementation and link to it.
puts <<"XEOF"
Before I do all kinds of cryptographic operations for you, I'd like some
cash, please. Don't worry, it's just hash cash.

Please enter a hash cash stamp for the resource '#{resource}'
with a value of #{required_bits} bits.
XEOF

read_and_check_hashcash(resource, required_bits)

puts "Thanks, now please paste your revocation blob, " \
     "followed by an empty line."
revo_blob = ""
while (line = STDIN.readline) != "\n" do
	revo_blob += line
end
revo_blob = Base64.decode64(revo_blob)

signature_file = Tempfile.new 'sig'
signature_file.write revo_blob
signature_file.close

# try to verify signature for all files in the accepted repo
g = Git.open(OpenCorn::Config['ACCEPTED_REPO'])

key_file_to_revoke = nil
g.ls_files.keys.each do |key_file|
	puts "running openssl rsautl -verify -in #{signature_file.path} " \
	     "-inkey #{OpenCorn::Config['ACCEPTED_REPO']}/#{key_file} " \
	     "-keyform DER -pubin"
	sig_result = `openssl rsautl -verify -in #{signature_file.path} \
	              -inkey #{OpenCorn::Config['ACCEPTED_REPO']}/#{key_file} \
	              -keyform DER -pubin`[-32,32]
	next if ($? != 0)
	if sig_result == File.read("#{OpenCorn::Config['ETC']}/revocation.txt") then
		key_file_to_revoke = key_file
		break
	end
end

if ! key_file_to_revoke then
	STDERR.puts "Sorry, no file to revoke found " \
	            "(maybe your revocation blob is wrong?"
	exit 3
end

g2 = Git.open(OpenCorn::Config['REVOCATION_REPO'])
g2.pull

File.copy(OpenCorn::Config['ACCEPTED_REPO'] + "/#{key_file_to_revoke}", \
          OpenCorn::Config['REVOCATION_REPO'])
g2.add key_file_to_revoke
g2.commit "[revoke] Self-revocation for #{key_file_to_revoke}"
g2.push

puts "OK, your key has been revoked now, thanks for caring!"
