require 'aws-sdk-eks'
require 'cloudformation/eks'
require 'config'
require 'log'

module EksCli
  module EKS
    class Cluster

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def create
        Log.info "creating cluster #{@cluster_name}"
        @config = CloudFormation::EKS.new(@cluster_name).create
        self
      end

      def config; @config; end

      def update_kubeconfig
        Log.info "updating kubeconfig for cluster #{@cluster_name}"
        Log.info `aws eks update-kubeconfig --name=#{@cluster_name} --region=#{Config[@cluster_name]["region"]}`
      end

    end
  end
end
