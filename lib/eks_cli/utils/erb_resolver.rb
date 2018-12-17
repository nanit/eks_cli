require 'ostruct'
require 'erb'

module EksCli
  class ERBResolver < OpenStruct
    def self.render(t, h)
      ERBResolver.new(h).render(t)
    end

    def render(template)
      ERB.new(template).result(binding)
    end
  end
end

