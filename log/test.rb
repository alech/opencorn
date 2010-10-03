load "log.rb"


OpenCorn::Log.instance() << "test"
OpenCorn::Log.instance() << "1"
#OpenCorn::Log.instance() << "2"
#OpenCorn::Log.instance() << "3"
#OpenCorn::Log.instance() << "4"

p OpenCorn::Log::prng("test")
