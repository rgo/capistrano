module Capistrano

  class Version

    CURRENT = File.read(File.dirname(__FILE__) + '/../../VERSION')

    MAJOR, MINOR, TINY = CURRENT.split(".",3).map{|n| n.to_i}

    STRING = CURRENT.to_s

    def self.to_s
      CURRENT
    end
    
  end

end
