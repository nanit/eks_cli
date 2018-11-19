require 'logger'
module EksCli
  class Log
    def self.info(str)
      self.logger.info str
    end

    def self.error(str)
      self.logger.error str
    end

    def self.debug(str)
      self.logger.debug str
    end

    def self.warn(str)
      self.logger.warn str
    end

    private

    def self.logger
      @logger ||= Logger.new(STDOUT)
    end
  end
end
