require 'singleton'
require 'yaml'

module OpenCorn
	class Config
		include Singleton
		attr_reader :cfg
		def initialize
			begin
				@cfg = open(File.join(File.expand_path('~'), '.opencorn.cfg')) do |f|
					YAML.load(f)
				end
			rescue Errno::ENOENT
				STDERR.puts "Error loading config file!"
				exit 10
			end
		end
		def self.[](key)
			self.instance.cfg[key]
		end
	end
end
