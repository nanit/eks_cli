require 'thor'
require 'version'

autoload :JSON, 'json'

module EksCli

  autoload :Config, 'config'
  autoload :NodeGroup, 'nodegroup'
  module CloudFormation
    autoload :Stack, 'cloudformation/stack'
  end
  module EKS
    autoload :Cluster, 'eks/cluster'
  end
  module K8s
    autoload :Auth, 'k8s/auth'
    autoload :Client, 'k8s/client'
  end
  module Route53
    autoload :Client, 'route53/client'
  end
  module VPC
    autoload :Client, 'vpc/client'
  end

  class Cli < Thor

    class_option :cluster_name, required: true, aliases: :c

    desc "create", "creates a new EKS cluster"
    option :region, type: :string, default: "us-west-2", desc: "AWS region for EKS cluster"
    option :kubernetes_version, type: :string, default: "1.10", desc: "EKS control plane version"
    option :cidr, type: :string, default: "192.168.0.0/16", desc: "CIRD block for cluster VPC"
    option :subnet1_az, type: :string, desc: "availability zone for subnet 01"
    option :subnet2_az, type: :string, desc: "availability zone for subnet 02"
    option :subnet3_az, type: :string, desc: "availability zone for subnet 03"
    option :open_ports, type: :array, default: [], desc: "open ports on cluster nodes (eg 22 for SSH access)"
    option :enable_gpu, type: :boolean, default: false, desc: "installs nvidia device plugin daemon set"
    option :create_default_storage_class, type: :boolean, default: false, desc: "creates a default gp2 storage class"
    option :create_dns_autoscaler, type: :boolean, default: true, desc: "creates dns autoscaler on the cluster"
    option :warm_ip_target, type: :numeric, desc: "set a default custom warm ip target for CNI"
    def create
      opts = {region: options[:region],
              kubernetes_version: options[:kubernetes_version],
              open_ports: options[:open_ports],
              cidr: options[:cidr],
              warm_ip_target: options[:warm_ip_target] ? options[:warm_ip_target].to_i : nil,
              subnet1_az: (options[:subnet1_az] || Config::AZS[options[:region]][0]),
              subnet2_az: (options[:subnet2_az] || Config::AZS[options[:region]][1]),
              subnet3_az: (options[:subnet3_az] || Config::AZS[options[:region]][2])}
      config.bootstrap(opts)
      cluster = EKS::Cluster.new(cluster_name).create
      config.write(cluster.config)
      cluster.update_kubeconfig
      wait_for_cluster
      enable_gpu if options[:enable_gpu]
      create_default_storage_class if options[:create_default_storage_class]
      create_dns_autoscaler if options[:create_dns_autoscaler]
      update_cluster_cni if options[:warm_ip_target]
      say "cluster creation completed"
    end

    desc "show-config", "print cluster configuration"
    option :group_name, desc: "group name to show configuration for"
    def show_config
      if options[:group_name]
        puts JSON.pretty_generate(Config[cluster_name].for_group(options[:group_name]))
      else
        puts JSON.pretty_generate(Config[cluster_name].read_from_disk)
      end
    end

    desc "update-cluster-cni", "updates cni with warm ip target"
    def update_cluster_cni
      K8s::Client.new(cluster_name).update_cni
    end

    desc "enable-gpu", "installs nvidia plugin as a daemonset on the cluster"
    def enable_gpu
      K8s::Client.new(cluster_name).enable_gpu
    end

    desc "set-docker-registry-credentials USERNAME PASSWORD EMAIL", "sets docker registry credentials"
    def set_docker_registry_credentials(username, password, email)
      K8s::Client.new(cluster_name).set_docker_registry_credentials(username, password, email)
    end

    desc "create-default-storage-class", "creates default storage class on a new k8s cluster"
    def create_default_storage_class
      K8s::Client.new(cluster_name).create_default_storage_class
    end

    desc "create-nodegroup", "creates all nodegroups on environment"
    option :all, type: :boolean, default: false, desc: "create all nodegroups. must be used in conjunction with --yes"
    option :group_name, type: :string, default: "Workers", desc: "create a specific nodegroup. can't be used with --all"
    option :ami, desc: "AMI for the nodegroup"
    option :instance_type, default: "m5.xlarge", desc: "EC2 instance type (m5.xlarge etc...)"
    option :subnets, type: :array, default: ["1", "2", "3"], desc: "subnets to run on. for example --subnets=1 3 will run the nodegroup on subnet1 and subnet 3"
    option :ssh_key_name, desc: "name of the default SSH key for the nodes"
    option :taints, desc: "Kubernetes taints to put on the nodes for example \"dedicated=critical:NoSchedule\""
    option :volume_size, type: :numeric, default: 100, desc: "disk size for node group in GB"
    option :min, type: :numeric, default: 1, desc: "minimum number of nodes on the nodegroup"
    option :max, type: :numeric, default: 1, desc: "maximum number of nodes on the nodegroup"
    option :desired, type: :numeric, default: 1, desc: "desired number of nodes on the nodegroup"
    option :enable_docker_bridge, type: :boolean, default: false, desc: "pass --enable-docker-bridge on bootstrap.sh (https://github.com/kubernetes/kubernetes/issues/40182))"
    option :yes, type: :boolean, default: false, desc: "perform nodegroup creation"
    def create_nodegroup
      opts = options.dup
      opts[:subnets] = opts[:subnets].map(&:to_i)
      Config[cluster_name].update_nodegroup(opts) unless opts[:all]
      if opts[:yes]
        cf_stacks = nodegroups.map {|ng| ng.create(wait_for_completion: false)}
        CloudFormation::Stack.await(cf_stacks)
        K8s::Auth.new(cluster_name).update
      end
    end

    desc "scale-nodegroup", "scales a nodegroup"
    option :group_name, type: :string, required: true, desc: "nodegroup name to scale"
    option :min, required: true, type: :numeric, desc: "Minimum number of nodes on the nodegroup"
    option :max, required: true, type: :numeric, desc: "Maximum number of nodes on the nodegroup"
    def scale_nodegroup
      NodeGroup.new(cluster_name, options[:group_name]).scale(options[:min].to_i, options[:max].to_i)
      Config[cluster_name].update_nodegroup(options)
    end

    desc "delete-nodegroup", "deletes cloudformation stack for nodegroup"
    option :all, type: :boolean, default: false, desc: "delete all nodegroups. can't be used with --name"
    option :group_name, type: :string, desc: "delete a specific nodegroup. can't be used with --all"
    def delete_nodegroup
      nodegroups.each(&:delete)
    end

    desc "update-auth", "update aws auth configmap to allow all nodegroups to connect to control plane"
    def update_auth
      K8s::Auth.new(cluster_name).update
    end

    desc "set-iam-policies", "sets IAM policies to be attached to created nodegroups"
    option :policies, type: :array, required: true, desc: "IAM policies ARNs"
    def set_iam_policies
      Config[cluster_name].set_iam_policies(options[:policies])
    end

    desc "update-dns HOSTNAME K8S_SERVICE_NAME", "alters route53 CNAME records to point to k8s service ELBs"
    option :route53_hosted_zone_id, required: true, desc: "hosted zone ID for the cname record on route53"
    option :elb_hosted_zone_id, required: true, desc: "hosted zone ID for the ELB on ec2"
    option :namespace, default: "default", desc: "the k8s namespace of the service"
    def update_dns(hostname, k8s_service_name)
      Route53::Client.new(cluster_name).update_dns(hostname, k8s_service_name, options[:namespace], options[:route53_hosted_zone_id], options[:elb_hosted_zone_id])
    end

    desc "set-inter-vpc-networking TO_VPC_ID TO_SG_ID", "creates a vpc peering connection, sets route tables and allows network access on SG"
    def set_inter_vpc_networking(to_vpc_id, to_sg_id)
      VPC::Client.new(cluster_name).set_inter_vpc_networking(to_vpc_id, to_sg_id)
    end

    desc "create-dns-autoscaler", "creates kube dns autoscaler"
    def create_dns_autoscaler
      K8s::Client.new(cluster_name).create_dns_autoscaler
    end

    desc "wait-for-cluster", "waits until cluster responds to HTTP requests"
    def wait_for_cluster
      K8s::Client.new(cluster_name).wait_for_cluster
    end

    desc "export-nodegroup", "exports nodegroup auto scaling group to spotinst"
    option :all, type: :boolean, default: false, desc: "create all nodegroups. must be used in conjunction with --yes"
    option :group_name, type: :string, desc: "create a specific nodegroup. can't be used with --all"
    option :exact_instance_type, type: :boolean, default: false, desc: "enforce spotinst to use existing instance type only"
    def export_nodegroup
      nodegroups.each {|ng| ng.export_to_spotinst(options[:exact_instance_type]) }
    end

    desc "add-iam-user IAM_ARN", "adds an IAM user as an authorized member on the EKS cluster"
    option :username, default: "admin", desc: "the username on the k8s cluster"
    option :groups, type: :array, default: ["system:masters"], desc: "which group should the user be added to"
    option :yes, type: :boolean, default: false, desc: "update aws-auth configmap"
    def add_iam_user(iam_arn)
      Config[cluster_name].add_user(iam_arn, options[:username], options[:groups])
      K8s::Auth.new(cluster_name).update if options[:yes]
    end

    disable_required_check! :version
    desc "version", "prints eks_cli version"
    def version
      puts EksCli::VERSION
    end

    no_commands do
      def cluster_name; options[:cluster_name]; end

      def config; Config[cluster_name]; end

      def all_nodegroups; Config[cluster_name]["groups"].keys ;end

      def nodegroups
        ng = options[:all] ? all_nodegroups : [options[:group_name]]
        ng.map {|n| NodeGroup.new(cluster_name, n)}
      end
    end

  end
end
