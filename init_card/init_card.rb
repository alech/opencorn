#!/usr/bin/env ruby

require 'tempfile'
require 'base64'
require 'opencorn/config'
require 'rubygems'
require 'git'

# delete card
print "Are you sure you want to delete the card? "
answer = STDIN.readline.chomp
if answer[0,1].downcase != 'y' then
	exit 1
end

if ! system "pkcs15-init -E" then
	STDERR.puts "Error running pkcs15-init -E"
	exit 2
end

# initialize PIN and PUK
nick = ""
print "Please enter your nickname (alphanumeric): "
nick = STDIN.readline.chomp[/^([a-zA-Z0-9]+)/, 1]

# TODO: PIN/PUK input using pinpad (:|... -p -)
if ! system "pkcs15-init --create-pkcs15 --profile pkcs15+onepin --use-default-transport-key --label '#{nick}'" then
	STDERR.puts "Error running pkcs15-init --create-pkcs15"
	exit 3
end

# create key
keysize = ''
while keysize != '1024' && keysize != '2048' do
	print "What is your preferred RSA key size (1024k or 2048k)? "
	keysize = STDIN.readline.chomp
end
if ! system "pkcs15-init --generate-key rsa/#{keysize} --auth-id 01" then
	STDERR.puts "Error running pkcs15-init --generate-key"
	exit 4
end

# create revocation blob
tf = Tempfile.new 'revo-blob-signed'
revo_blob = `pkcs15-crypt -s -i #{File.dirname(File.expand_path $0)}/revocation.txt -o #{tf.path} --pkcs1 --sha-256`
if $? != 0 then
	STDERR.puts "Error creating revocation blob."
	exit 5
end
puts "Your revocation blob, please keep this safe in case you need to revoke your key"
puts Base64.encode64(tf.read)
system "wipe -f -i #{tf.path}"

# store key in git repository and push it to origin
keys = `pkcs15-tool -k`
key_id = keys[/ID          : ([a-f0-9]+)/, 1]
key_der = `pkcs15-tool --read-public-key #{key_id} | openssl rsa -pubin -inform PEM -outform DER`
if key_der.size == 0 then
	STDERR.puts "Error reading public key from card."
	exit 6
end

File.open "#{OpenCorn::Config['ACCEPTED_REPO']}/#{nick}.der", 'w' do |f| f.write key_der end
g = Git.open(OpenCorn::Config['ACCEPTED_REPO'])
g.add "#{nick}.der"
g.pull
commit_id = g.commit("[init_card] #{nick}.der")[/([0-9a-f]+)\]/, 1]
g.push

# TODO: send revo blob encrypted to board members
# together with commit ID, so that they know what to tag
