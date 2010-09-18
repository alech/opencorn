#!/usr/bin/env ruby

require 'tempfile'
require 'base64'
#require 'opencorn/config'
# FIXME: path from config
KEYPATH = '/tmp'

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

# TODO: check that the PIN/PUK can be input using pinpad
system "pkcs15-init --create-pkcs15 --profile pkcs15+onepin --use-default-transport-key --label '#{nick}'"

# create key
keysize = ''
while keysize != '1024' && keysize != '2048' do
    print "What is your preferred RSA key size (1024k or 2048k)? "
    keysize = STDIN.readline.chomp
end
system "pkcs15-init --generate-key rsa/#{keysize} --auth-id 01"

# store key
keys = `pkcs15-tool -k`
key_id = keys[/ID          : ([a-f0-9]+)/, 1]
key_der = `pkcs15-tool --read-public-key #{key_id} | openssl rsa -pubin -inform PEM -outform DER`
File.open "#{KEYPATH}/#{nick}.der", 'w' do |f| f.write key_der end
# TODO: git commit

# create revocation blob
tf = Tempfile.new 'revo-blob-signed'
revo_blob = `pkcs15-crypt -s -i revocation.txt --pkcs1 --sha-1 -o #{tf.path}`
puts "Your revocation blob, please keep this safe in case you need to revoke your key"
puts Base64.encode64(tf.read)
system "wipe -f -i #{tf.path}"

# TODO: send revo blob encrypted to board members
# together with commit ID, so that they know what to tag
