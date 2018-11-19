require 'aws-sdk-cloudformation'
require 'config'
module EksCli
  module CloudFormation
    class Client
      def self.get(cluster_name)
        @client ||= Aws::CloudFormation::Client.new(region: Config[cluster_name]["region"])
      end
    end
  end
end
