require 'yaml'
require 'kubeclient'

module EksCli
  module K8s
    class ConfigmapBuilder
      class << self
        def build(arns)
          cm = Kubeclient::Resource.new
          cm.metadata={}
          cm.metadata.name = "aws-auth"
          cm.metadata.namespace = "kube-system"
          cm.data = {}
          cm.data.mapRoles = map_roles(arns)
          cm
        end

        def map_roles(arns)
          arns.map {|a| map_role(a)}.to_yaml.sub("---\n","")
        end

        def map_role(stack_arn)
          {"rolearn" => stack_arn,
           "username" => "system:node:{{EC2PrivateDNSName}}",
           "groups" => ["system:bootstrappers", "system:nodes"]}
        end
      end
    end
  end
end
