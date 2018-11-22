require 'k8s/configmap_builder'
require 'k8s/client'
require 'config'
require 'cloudformation/client'
require 'cloudformation/stack'
require 'log'

module EksCli
  module K8s
    class Auth

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def update
        Log.info "updating auth configmap on kubernetes"
        begin
          k8s_client.get_config_map("aws-auth", "kube-system")
          k8s_client.update_config_map(configmap)
        rescue KubeException => e
          Log.debug "exception updating configmap: #{e}"
          k8s_client.create_config_map(configmap)
        end
        Log.info "done"
      end

      private
      
      def k8s_client
        @k8s_client ||= K8s::Client.new(@cluster_name)
      end

      def client
        CloudFormation::Client.get(@cluster_name)
      end

      def node_arns
        client
          .list_stacks(stack_status_filter: ["CREATE_COMPLETE"])
          .stack_summaries
          .map(&:stack_id)
          .map {|id| CloudFormation::Stack.new(@cluster_name, id)}
          .select {|stack| stack.eks_worker?}
          .map {|stack| stack.node_instance_role_arn}
      end

      def users
        Config[@cluster_name]["users"]
      end

      def configmap
        ConfigmapBuilder.build(node_arns, users)
      end

    end
  end
end
