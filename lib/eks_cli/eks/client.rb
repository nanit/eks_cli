require 'aws-sdk-eks'
require 'config'
module EksCli
  module EKS
    class Client
      def self.get(cluster_name)
        @client ||= Aws::EKS::Client.new(region: Config[cluster_name]["region"])
      end
    end
  end
end
