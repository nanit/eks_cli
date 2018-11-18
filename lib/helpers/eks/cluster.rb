require 'aws-sdk-eks'
require 'eks/client'
require 'config'
require 'log'

module EKS
  class Cluster

    def initialize(cluster_name)
      @cluster_name = cluster_name
    end

    def create
      Log.info "creating cluster #{@cluster_name}"
      Log.debug config
      resp = client.create_cluster(config)
      Log.info "response: #{resp.cluster}"
      self
    end

    def config
      {name: @cluster_name,
       role_arn: Config[@cluster_name]["eks_role_arn"],
       resources_vpc_config: {
         subnet_ids: Config[@cluster_name]["subnets"],
         security_group_ids:  [Config[@cluster_name]["control_plane_sg_id"]]}}
    end

    def await
      while status == "CREATING" do
        Log.info "waiting for cluster #{@cluster_name} to finish creation (#{status})"
        sleep 10
      end
      Log.info "cluster #{@cluster_name} created with status #{status}"
    end

    def status
      cluster.status
    end

    def cluster
      client.describe_cluster(name: @cluster_name).cluster
    end

    def arn
      cluster.arn
    end

    def client
      Client.get(@cluster_name)
    end

    def update_kubeconfig
      Log.info "updating kubeconfig for cluster #{@cluster_name}"
      Log.info `aws eks update-kubeconfig --name=#{@cluster_name} --region=#{Config[@cluster_name]["region"]}`
    end

  end
end
