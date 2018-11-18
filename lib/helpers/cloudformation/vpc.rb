require 'cloudformation/stack'
require 'log'

module CloudFormation
  class VPC

    def self.create(cluster_name)
      Log.info "creating VPC stack for #{cluster_name}"
      s = Stack.create(cluster_name, config(cluster_name))
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

    def self.config(cluster_name)
      {stack_name: "EKS-VPC-#{cluster_name}",
       template_url: "https://amazon-eks.s3-us-west-2.amazonaws.com/cloudformation/2018-08-30/amazon-eks-vpc-sample.yaml",
       tags: [{key: "eks-cluster", value: cluster_name.to_s}]}
    end

  end
end
