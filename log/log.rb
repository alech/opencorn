require 'openssl'
require 'base64'
require 'opencorn/config'
require 'gpgme'
require 'singleton'


module OpenCorn
  class Log
    include Singleton
    @seed = nil

    def initialize
      @seed=nil
      @seed = OpenSSL::Random::random_bytes(128)
      gpgdata = GPGME::Data.from_str(@seed)
      gpgkeys = GPGME.list_keys(OpenCorn::Config['GPG_LOG_KEYID'])
      raise "Too many keys for this KeyID" unless gpgkeys.size == 1
      gpgout = GPGME.encrypt(gpgkeys,gpgdata)
      #preceding 00 01 indicates a new seed for the prng encrypted with
      writeLog("\x00\x01"+Base64::encode64(gpgout))
      puts "OpenCorn::Log initialized"
    end
    
    def self.prng(seed)
       ctx = Digest::SHA512
       [ctx.digest("0"+seed),ctx.digest("1"+seed)]
    end

    def writeLog(msg)
      fp = File.open(OpenCorn::Config['LOG_FILE'],"a")
      fp.write(msg)
      fp.close
    end

    def getRand()
        @seed,out = Log::prng(@seed)
        out
    end

    def cryptMsg(msg)
        myrand = getRand()
        ctx = OpenSSL::Cipher::AES256.new("OFB")
        ctx.iv  = myrand[0..15]  #128bit iv
        ctx.key = myrand[16..47] #256bit key
        ctext = ctx.update(msg)+ctx.final()
        out = OpenSSL::HMAC.digest("SHA1",myrand[48..63],ctext)+ctext 
        #preceding 00 indicates that the base64 string is as symmetric
        #encrypted logentry
        writeLog("\x00"+Base64::encode64(out))
    end
    alias << cryptMsg
  end
end
