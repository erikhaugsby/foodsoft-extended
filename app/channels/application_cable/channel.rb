module ApplicationCable
  class Channel < ActionCable::Channel::Base
    def self.broadcasting
      "#{FoodsoftConfig.scope}::#{name}"
    end
  end
end
