require 'httparty'
require 'log'
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
        body = instance_types ? {group: {spotInstanceTypes: instance_types}} : {}
        self.class.post("/aws/ec2/group/autoScalingGroup/import?region=#{region}&accountId=#{@account_id}&autoScalingGroupName=#{asg_name}",
                        body: body.to_json)
      end

      def list_groups
        self.class.get("/aws/ec2/group?accountId=#{@account_id}")
      end

      def scale(group_id, min, max)
        Log.info "scaling elastigroup #{group_id} {#{min}, #{max}}"
        Log.info self.class.put("/aws/ec2/group/#{group_id}/capacity?accountId=#{@account_id}", body: {capacity: {minimum: min, maximum: max, target: max}}.to_json)
      end

      def delete_elastigroup(group_id)
        Log.info "deleting elastigroup #{group_id}"
        Log.info self.class.delete("/aws/ec2/group/#{group_id}?accountId=#{@account_id}")
      end
    end
  end
end
