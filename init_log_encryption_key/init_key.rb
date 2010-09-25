#!/usr/bin/env ruby

require 'rubygems'
require 'fileutils'
require 'secretsharing'
require 'gpgme'
require 'opencorn/config'
require 'base64'
require 'tempfile'
require 'mail'

DEBUG = false

def count_board_member_keys
	old_env = ENV['GNUPGHOME']
	ENV['GNUPGHOME'] = OpenCorn::Config['GNUPGHOME']
	gpg = GPGME::Ctx.new
	amount = gpg.keys.select { |k| k.owner_trust < 5 }.size
	ENV['GNUPGHOME'] = old_env
	amount
end

def mail_shares_to_board_members
end

def create_gpg_key(passphrase, k, n)
	ctx = GPGME::Ctx.new
	key_params =<<"XEOF"
<GnupgKeyParms format="internal">
Key-Type: DSA
Key-Length: 1536
Subkey-Type: ELG-E
Subkey-Length: 1536
Name-Real: OpenCorn Logging key
Name-Comment: passphrase #{k}/#{n} secret shared
Name-Email: #{OpenCorn::Config['MAIL_FROM']}
Expire-Date: #{OpenCorn::Config['LOGKEY_EXPIRY']}
Passphrase: #{passphrase}
</GnupgKeyParms>
XEOF
	puts "Generating key, this may take a while ..."
	ctx.generate_key(key_params, nil, nil)
	puts "Key generated."
end

tmpdir = Dir.mktmpdir
ENV['GNUPGHOME'] = tmpdir

n = count_board_member_keys
k = OpenCorn::Config['SECRETSHARING_K']
s = SecretSharing::Shamir.new(n, k)
s.create_random_secret

puts passphrase if DEBUG
create_gpg_key(s.secret_password, k, n)

# TODO: export public key to GNUPGHOME_LOG keyring

# send encrypted mails to board members with shares and secring/pubring
ENV['GNUPGHOME'] = OpenCorn::Config['GNUPGHOME']

gpg = GPGME::Ctx.new
i = 0
gpg.each_key do |key|
	next if key.owner_trust == 5 # this is our own key
	plain_body = "A new logging key has been created. Your secret share is the following:\n" \
	           + "#{s.shares[i]}\n\n" \
	           + "Find the encrypted secring.gpg and pubring.pgp attached."
	enc_body = GPGME.encrypt([key], plain_body, {:armor => true, :always_trust => true})
	File.open "#{tmpdir}/secring.gpg.gpg", 'w' do |f|
		f.write GPGME.encrypt([key], File.read("#{tmpdir}/secring.gpg"), {:always_trust => true})
	end
	File.open "#{tmpdir}/pubring.gpg.gpg", 'w' do |f|
		f.write GPGME.encrypt([key], File.read("#{tmpdir}/pubring.gpg"), {:always_trust => true})
	end
	mail = Mail.new do
		from OpenCorn::Config['MAIL_FROM']
		to key.uids[0].email
		subject "OpenCorn logging key and passphrase secret share"
		body enc_body
		add_file "#{tmpdir}/secring.gpg.gpg"
		add_file "#{tmpdir}/pubring.gpg.gpg"
	end
	mail.deliver
	i += 1
end
