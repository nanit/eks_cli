require 'aws-sdk-iam'
require 'config'
module EksCli
  module IAM
    class Client

      EKS_CLUSTER_POLICIES = ["AmazonEKSClusterPolicy", "AmazonEKSServicePolicy"]
      ASSUME_ROLE = {
        "Version" => "2012-10-17",
        "Statement" => [
          {
            "Effect" => "Allow",
            "Principal" => {
              "Service" => "eks.amazonaws.com"
            },
            "Action" => "sts:AssumeRole"
          }
        ]
      }

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def client
        @client ||= Aws::IAM::Client.new(region: config["region"])
      end

      def config
        @config ||= Config[@cluster_name]
      end

      def create_eks_role
        Log.info "creating IAM cluster role for #{@cluster_name}"
        begin 
          role = client.get_role(role_name: role_name).role
        rescue Aws::IAM::Errors::NoSuchEntity => e
          role = client.create_role(role_name: role_name,
                                    description: "created by eks cli for #{@cluster_name}",
                                    assume_role_policy_document: ASSUME_ROLE.to_json).role
          attach_policies(role.role_name, EKS_CLUSTER_POLICIES)
        end
        Log.info "created role #{role}"
        role
      end

      def attach_node_policies(role_name)
        attach_policies(role_name, node_policies)
      end

      def detach_node_policies(role_name)
        detach_policies(role_name, node_policies)
      end

      def attach_policies(role_name, policies)
        Log.info "attaching IAM policies to #{role_name}"
        policies.each do |p|
          client.attach_role_policy(policy_arn: arn(p),
                                    role_name: role_name)
        end
      end

      def detach_policies(role_name, policies)
        Log.info "detaching IAM policies to #{role_name}"
        policies.each do |p|
          client.detach_role_policy(policy_arn: arn(p),
                                    role_name: role_name)
        end
      end

      def node_policies
        config["iam_policies"]
      end

      def arn(p)
        "arn:aws:iam::aws:policy/#{p}"
      end

      def role_name
        "#{@cluster_name}-EKS-Role"
      end
    end
  end
end
