require 'yaml'
require 'kubeclient'
require_relative '../log'
require_relative '../config'

module EksCli
  module K8s
    class Client

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def get_elb(service_name, ns = "default")
        self.get_service(service_name, ns).status.loadBalancer.ingress.first.hostname
      end

      def enable_gpu
        self.create_daemon_set(resource_from_yaml("nvidia_device_plugin.yaml"))
      end

      def set_docker_registry_credentials(user, password, email)
        Log.info "setting docker registry credentials"
        Log.info `kubectl config use-context #{config["cluster_arn"]} &&
         kubectl create secret docker-registry registrykey --docker-server=https://index.docker.io/v1/ --docker-username=#{user} --docker-password=#{password} --docker-email=#{email} &&
         kubectl --namespace=kube-system create secret docker-registry registrykey --docker-server=https://index.docker.io/v1/ --docker-username=#{user} --docker-password=#{password} --docker-email=#{email}`

        Log.info client.patch_service_account("default", {imagePullSecrets: [{name: "registrykey"}]}, "default")
        Log.info client.patch_service_account("default", {imagePullSecrets: [{name: "registrykey"}]}, "kube-system")
      end

      def create_default_storage_class
        Log.info "creating default storage class"
        Log.info self.create_storage_class(resource_from_yaml("default_storage_class.yaml"))
      end

      def create_dns_autoscaler
        Log.info "creating kube-dns autoscaler"
        Log.info self.create_deployment(resource_from_yaml("dns_autoscaler.dep.yaml"))
      end

      private

      def resource_from_yaml(filename)
        yaml = YAML.load_file(File.join($root_dir, "/assets/#{filename}"))
        Kubeclient::Resource.new(yaml)
      end

      def method_missing(method, *args, &block)
        if v1_client.respond_to?(method)
          v1_client.send(method, *args, &block)
        elsif apps_client.respond_to?(method)
          apps_client.send(method, *args, &block)
        elsif storage_client.respond_to?(method)
          storage_client.send(method, *args, &block)
        else
          raise "unknown method #{method}"
        end
      end

      def apps_client
        @apps_client ||= client("/apis/apps")
      end

      def v1_client
        @v1_client ||= client
      end

      def storage_client
        @storage_client ||= client("/apis/storage.k8s.io")
      end

      def client(suffix = "")
        Kubeclient::Client.new(
          [context.api_endpoint, suffix].join,
          context.api_version,
          ssl_options: context.ssl_options,
          auth_options: {bearer_token: token})
      end

      def config
        @config ||= Config[@cluster_name]
      end

      def token
        JSON.parse(`aws-iam-authenticator token -i #{config["cluster_name"]}`)["status"]["token"]
      end

      def kube_config
        @kube_config ||= Kubeclient::Config.read("#{ENV['HOME']}/.kube/config")
      end

      def context
        kube_config.context(config["cluster_arn"])
      end


    end
  end
end
