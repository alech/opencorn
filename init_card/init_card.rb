#!/usr/bin/env ruby

require 'tempfile'
require 'base64'
require 'opencorn/config'
require 'rubygems'
require 'git'
require 'gpgme'
require 'mail'

DEBUG = true

def run_tool(toolname, options, backticks = false)
	if OpenCorn::Config['PINPAD'] then
		if toolname == 'pkcs15-init' then
			command = "#{toolname} --no-prompt #{options}"
		else
			command = ":|#{toolname} -p - #{options}"
		end
	else
		command = "#{toolname} #{options}"
	end
	puts "running #{command}" if DEBUG
	if backticks then
		`#{command}`
	else
		system "#{command}"
	end
end

# delete card
print "Are you sure you want to delete the card? "
answer = STDIN.readline.chomp
if answer[0,1].downcase != 'y' then
	exit 1
end

if ! system("pkcs15-init", "-E") then
	STDERR.puts "Error running pkcs15-init -E"
	exit 2
end

# initialize PIN and PUK
nick = ""
print "Please enter your nickname (alphanumeric): "
nick = STDIN.readline.chomp[/^([a-zA-Z0-9]+)/, 1]

if ! run_tool("pkcs15-init",  "--create-pkcs15 --profile pkcs15+onepin " \
              "--use-default-transport-key --label '#{nick}'") then
	STDERR.puts "Error running pkcs15-init --create-pkcs15"
	exit 3
end

# create key
keysize = ''
while keysize != '1024' && keysize != '2048' do
	print "What is your preferred RSA key size (1024 or 2048)? "
	keysize = STDIN.readline.chomp
end
if ! run_tool("pkcs15-init", "--generate-key rsa/#{keysize} --auth-id 01") then
	STDERR.puts "Error running pkcs15-init --generate-key"
	exit 4
end

# create revocation blob
tf = Tempfile.new 'revo-blob-signed'
revo_blob = run_tool("pkcs15-crypt", "-s -i " \
                     "#{OpenCorn::Config['ETC']}/revocation.txt " \
                     "-o #{tf.path} --pkcs1 --sha-256", true)
if $? != 0 then
	STDERR.puts "Error creating revocation blob."
	exit 5
end
puts "Your revocation blob, please keep this safe in case you need " \
     "to revoke your key"
puts Base64.encode64(tf.read)
system "wipe -f -i #{tf.path}"

# store key in git repository and push it to origin
keys = run_tool("pkcs15-tool", "-k", true)
key_id = keys[/ID          : ([a-f0-9]+)/, 1]
key_der = run_tool("pkcs15-tool",  "--read-public-key #{key_id} | openssl " \
                                   "rsa -pubin -inform PEM -outform DER", true)
if key_der.size == 0 then
	STDERR.puts "Error reading public key from card."
	exit 6
end

File.open "#{OpenCorn::Config['ACCEPTED_REPO']}/#{nick}.der", 'w' do |f|
	f.write key_der
end
g = Git.open(OpenCorn::Config['ACCEPTED_REPO'])
g.add "#{nick}.der"
g.pull
commit_id = g.commit("[init_card] #{nick}.der")[/([0-9a-f]+)\]/, 1]
g.push

# send commit ID and nickname to board members (email addresses from keyring)
if OpenCorn::Config['GNUPGHOME'] then
	ENV['GNUPGHOME'] = OpenCorn::Config['GNUPGHOME']
end
gpg = GPGME::Ctx.new
gpg.each_key do |key|
	next if key.owner_trust == 5 # this is our own key
	mail = Mail.new do
		from OpenCorn::Config['MAIL_FROM']
		to key.uids[0].email
		subject "New key for #{nick}, please tag #{commit_id}"
		body "A new key for #{nick} has been added to the repository using " \
		     "init_card.\n" \
		     "Please create a signed tag for git commit #{commit_id}."
	end
	mail.deliver
end
