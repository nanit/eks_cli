require 'cloudformation/eks'
require 'vpc/client'
require 'config'
require 'nodegroup'
require 'log'

module EksCli
  module EKS
    class Cluster

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def create
        Log.info "creating cluster #{@cluster_name}"
        cf_stack_outputs = CloudFormation::EKS.new(@cluster_name).create
        config.write(cf_stack_outputs)
        self
      end

      def delete
        delete_vpc_peering
        delete_services
        delete_nodegroups
        delete_cf_stack
        delete_config
      end

      def config; Config[@cluster_name]; end

      def update_kubeconfig
        Log.info "updating kubeconfig for cluster #{@cluster_name}"
        Log.info `aws eks update-kubeconfig --name=#{@cluster_name} --region=#{config["region"]}`
      end

      private

      def delete_config
        config.delete
      end

      def delete_cf_stack
        CloudFormation::EKS.new(@cluster_name).delete
      end

      def delete_vpc_peering
        VPC::Client.new(@cluster_name).delete_vpc_peering_connection
      end

      def k8s_client
        @k8s_client ||= EksCli::K8s::Client.new(@cluster_name)
      end

      def services
        k8s_client.get_services(namespace: "default").select {|s| s[:spec][:type] == "LoadBalancer"}
      end

      def delete_services
        services.map {|s| s[:metadata][:name]}.each do |s|
          Log.info "deleting service #{s}"
          k8s_client.delete_service(s, "default")
        end
      end

      def nodegroups
        config["groups"] || {}
      end

      def delete_nodegroups
        nodegroups.keys.each {|n| NodeGroup.new(@cluster_name, n).delete}
      end

    end
  end
end
