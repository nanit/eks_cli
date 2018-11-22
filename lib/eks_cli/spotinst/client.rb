require 'httparty'
module EksCli
  module Spotinst
    class Client 
      include HTTParty

      base_uri "https://api.spotinst.io"

      def initialize(account_id: nil, api_token: nil)
        @account_id = account_id || ENV['SPOTINST_ACCOUNT_ID']
        @api_token = api_token || ENV['SPOTINST_API_TOKEN']
        if @account_id == nil
          raise "please set SPOTINST_ACCOUNT_ID environment variable"
        end

        if @api_token == nil
          raise "please set SPOTINST_API_TOKEN environment variable"
        end
        self.class.headers({"Authorization" => "Bearer #{@api_token}",
                            "Content-Type" => "application/json"})
      end

      def import_asg(region, asg_name, instance_types)
        self.class.post("/aws/ec2/group/autoScalingGroup/import?region=#{region}&accountId=#{@account_id}&autoScalingGroupName=#{asg_name}",
                        body: {group: {spotInstanceTypes: instance_types} }.to_json)
      end

      def list_groups
        self.class.get("/aws/ec2/group?accountId=#{@account_id}")
      end
    end
  end
end
