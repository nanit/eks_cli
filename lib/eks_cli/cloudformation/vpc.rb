require 'cloudformation/stack'
require 'config'
require 'ipaddress'
require 'log'

module EksCli
  module CloudFormation
    class VPC

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def create
        Log.info "creating VPC stack for #{@cluster_name}"
        s = Stack.create(@cluster_name, cf_config)
        Stack.await([s])
        s.reload
        puts "Outputs are:
          SecurityGroups: #{s.output("SecurityGroups")}
          VpcId: #{s.output("VpcId")}
          SubnetIds: #{s.output("SubnetIds")}
        "
        {control_plane_sg_id: s.output("SecurityGroups"),
         vpc_id: s.output("VpcId"),
         subnets: s.output("SubnetIds").split(",")}
      end

      private

      def cf_config
        {stack_name: stack_name,
         template_body: cf_template_body,
         parameters: build_params,
         tags: tags}
      end

      def cf_template_body
        @cf_template_body ||= File.read(File.join($root_dir, '/assets/eks_vpc_cf_template.yaml'))
      end

      def stack_name
        "#{@cluster_name}-EKS-VPC"
      end

      def tags
        [{key: "eks-cluster", value: @cluster_name.to_s}]
      end

      def build_params
        subnets = IPAddress::IPv4.new(cidr).split(3).map(&:to_string)

        {"VpcBlock" => cidr,
         "Subnet01Block" => subnets[0],
         "Subnet02Block" => subnets[1],
         "Subnet03Block" => subnets[2],
         "Subnet01AZ" => config["subnet1_az"],
         "Subnet02AZ" => config["subnet2_az"],
         "Subnet03AZ" => config["subnet3_az"]}.map do |(k,v)|
          {parameter_key: k, parameter_value: v}
        end

      end

      def cidr
        @cidr ||= config["cidr"]
      end

      def config
        @config ||= Config[@cluster_name]
      end

    end
  end
end
