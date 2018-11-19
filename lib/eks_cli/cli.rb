require 'thor'

autoload :JSON, 'json'

module EksCli

  autoload :Config, 'config'
  autoload :NodeGroup, 'nodegroup'
  module CloudFormation
    autoload :Stack, 'cloudformation/stack'
    autoload :VPC, 'cloudformation/vpc'
  end
  module EKS
    autoload :Cluster, 'eks/cluster'
  end
  module K8s
    autoload :Auth, 'k8s/auth'
    autoload :Client, 'k8s/client'
  end
  module EC2
    autoload :SecurityGroup, 'ec2/security_group'
  end
  module IAM
    autoload :Client, 'iam/client'
  end
  module Route53
    autoload :Client, 'route53/client'
  end
  module VPC
    autoload :Client, 'vpc/client'
  end

  class Cli < Thor

    class_option :cluster_name, required: true, aliases: :c

    desc "bootstrap REGION", "bootstrap cluster configuration"
    def bootstrap(region)
      role = IAM::Client.new(cluster_name).create_eks_role
      Config[cluster_name].bootstrap({region: region, eks_role_arn: role.arn})
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

    desc "create-cluster-vpc", "creates a vpc according to aws cloudformation template"
    def create_cluster_vpc
      cfg = CloudFormation::VPC.create(cluster_name)
      Config[cluster_name].write(cfg)
    end

    desc "create-eks-cluster", "create EKS cluster on AWS"
    def create_eks_cluster
      cluster = EKS::Cluster.new(cluster_name).create
      cluster.await
      Config[cluster_name].write({cluster_arn: cluster.arn})
      cluster.update_kubeconfig
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
    option :group_name, type: :string, desc: "create a specific nodegroup. can't be used with --all"
    option :ami, desc: "AMI for the nodegroup"
    option :instance_type, desc: "EC2 instance type (m5.xlarge etc...)"
    option :num_subnets, type: :numeric, desc: "Number of subnets (AZs) to spread the nodegroup across"
    option :ssh_key_name, desc: "Name of the default SSH key for the nodes"
    option :taints, desc: "Kubernetes taints to put on the nodes for example \"dedicated=critical:NoSchedule\""
    option :min, type: :numeric, desc: "Minimum number of nodes on the nodegroup"
    option :max, type: :numeric, desc: "Maximum number of nodes on the nodegroup"
    option :yes, type: :boolean, default: false, desc: "Perform nodegroup creation"
    def create_nodegroup
      Config[cluster_name].update_nodegroup(options) unless options[:all]
      if options[:yes]
        cf_stacks = nodegroups.map {|ng| ng.create(wait_for_completion: false)}
        CloudFormation::Stack.await(cf_stacks)
        cf_stacks.each {|s| IAM::Client.new(cluster_name).attach_node_policies(s.node_instance_role_name)}
        K8s::Auth.new(cluster_name).update
      end
    end

    desc "delete-nodegroup", "deletes cloudformation stack for nodegroup"
    option :all, type: :boolean, default: false, desc: "delete all nodegroups. can't be used with --name"
    option :name, type: :string, desc: "delete a specific nodegroup. can't be used with --all"
    def delete_nodegroup
      nodegroups.each(&:delete)
    end

    desc "update-auth", "update aws auth configmap to allow all nodegroups to connect to control plane"
    def update_auth
      K8s::Auth.new(cluster_name).update
    end

    desc "detach-iam-policies", "detaches added policies to nodegroup IAM Role"
    option :all, type: :boolean, default: false, desc: "detach from all nodegroups. can't be used with --name"
    option :name, type: :string, desc: "detach from a specific nodegroup. can't be used with --all"
    def detach_iam_policies
      nodegroups.each(&:detach_iam_policies)
    end

    desc "set-iam-policies", "sets IAM policies to be attached to created nodegroups"
    option :policies, type: :array, required: true, desc: "IAM policies ARNs"
    def set_iam_policies
      Config[cluster_name].set_iam_policies(options[:policies])
    end

    desc "create-cluster-security-group", "creates a SG for cluster communication"
    option :open_ports, type: :array, default: [], desc: "open ports on cluster nodes"
    def create_cluster_security_group
      open_ports = options[:open_ports].map(&:to_i)
      gid = EC2::SecurityGroup.new(cluster_name, open_ports).create
      Config[cluster_name].write({nodes_sg_id: gid})
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

    no_commands do
      def cluster_name; options[:cluster_name]; end

      def all_nodegroups; Config[cluster_name]["groups"].keys ;end

      def nodegroups
        ng = options[:group_name] ? [options[:group_name]] : all_nodegroups
        ng.map {|n| NodeGroup.new(cluster_name, n)}
      end
    end

  end
end
