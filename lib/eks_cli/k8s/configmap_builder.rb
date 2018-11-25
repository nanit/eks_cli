require 'yaml'
require 'kubeclient'

module EksCli
  module K8s
    class ConfigmapBuilder
      class << self
        def build(node_arns, users)
          cm = Kubeclient::Resource.new
          cm.metadata={}
          cm.metadata.name = "aws-auth"
          cm.metadata.namespace = "kube-system"
          cm.data = {}
          cm.data.mapRoles = map_roles(node_arns)
          cm.data.mapUsers = map_users(users) if users && !users.empty?
          cm
        end

        def map_roles(node_arns)
          node_arns.map {|a| map_role(a)}.to_yaml.sub("---\n","")
        end

        def map_users(users)
          users.map {|arn, attrs| to_user_obj(arn, attrs["username"], attrs["groups"]) }.to_yaml.sub("---\n","")
        end

        def map_role(stack_arn)
          to_role_obj(stack_arn, "system:node:{{EC2PrivateDNSName}}", ["system:bootstrappers", "system:nodes"])
        end

        def to_auth_obj(type, arn, username, groups)
          {"#{type}arn" => arn,
           "username" => username,
           "groups" => groups}
        end

        def to_role_obj(arn, username, groups)
          to_auth_obj("role", arn ,username, groups)
        end

        def to_user_obj(arn, username, groups)
          to_auth_obj("user", arn ,username, groups)
        end

      end
    end
  end
end
