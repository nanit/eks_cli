require 'active_support/core_ext/hash'
require 'config'
require 'spotinst/client'
require 'cloudformation/stack'
require 'iam/client'
require 'k8s/auth'
require 'log'

module EksCli
  class NodeGroup

    T = {cluster_name: "ClusterName",
         control_plane_sg_id: "ClusterControlPlaneSecurityGroup",
         nodes_sg_id: "ClusterSecurityGroup",
         min: "NodeAutoScalingGroupMinSize",
         max: "NodeAutoScalingGroupMaxSize",
         instance_type: "NodeInstanceType",
         ami: "NodeImageId",
         volume_size: "NodeVolumeSize",
         ssh_key_name: "KeyName",
         vpc_id: "VpcId",
         subnets: "Subnets",
         group_name: "NodeGroupName",
         bootstrap_args: "BootstrapArguments"}

    AMIS = {"us-west-2" => "ami-0a54c984b9f908c81",
            "us-east-1" => "ami-0440e4f6b9713faf6",
            "us-east-2" => "ami-0958a76db2d150238",
            "us-west-1" => "ami-00c3b2d35bddd4f5c"}

    GPU_AMIS = {"us-west-2" => "ami-08156e8fd65879a13",
                "us-east-1" => "ami-0c974dde3f6d691a1",
                "us-east-2" => "ami-089849e811ace242f",
                "us-west-1" => "ami-0c3479bcd739094f0"}

    CAPABILITIES = ["CAPABILITY_IAM"]

    def initialize(cluster_name, name)
      @cluster_name = cluster_name
      @name = name
      @group = Config[cluster_name].for_group(name)
    end

    def create(wait_for_completion: true)
      Log.info "creating stack for nodegroup #{@group["group_name"]}"
      stack = CloudFormation::Stack.create(@cluster_name, cloudformation_config)
      Log.info "stack created - #{@group["group_name"]} - #{stack.id}"
      if wait_for_completion
        await(stack)
      end
      stack
    end

    def tags
      [{key: "eks-nodegroup", value: @group["group_name"]},
       {key: "eks-cluster", value: @cluster_name}]
    end

    def detach_iam_policies
      IAM::Client.new(@cluster_name).detach_node_policies(cf_stack.node_instance_role_name)
    end

    def delete
      detach_iam_policies
      cf_stack.delete
    end

    def asg
      cf_stack.resource("NodeGroup")
    end

    def instance_type
      @group["instance_type"]
    end

    def export_to_spotinst
      Log.info "exporting nodegroup #{@name} to spotinst"
      Log.info Spotinst::Client.new.import_asg(config["region"], asg, [instance_type])
    end

    def cf_stack
      CloudFormation::Stack.find(@cluster_name, stack_name)
    rescue Aws::CloudFormation::Errors::ValidationError => e
      Log.error("could not find stack for nodegroup #{@name} - please make sure to run eks create-nodegroup --all --yes -c <cluster_name> to sync config")
      raise e
    end

    private

    def cf_template_body
      @cf_template_body ||= File.read(File.join($root_dir, '/assets/nodegroup_cf_template.yaml'))
    end

    def await(stack)

      while stack.pending? do
        Log.info "waiting for stack #{stack.id} - status is #{stack.status}"
        sleep 10
      end

      Log.info "stack completed with status #{stack.status}"

      K8s::Auth.new(@cluster_name).update
      IAM::Client.new(@cluster_name).attach_node_policies(stack.node_instance_role_name)
    end

    def cloudformation_config
      {stack_name: stack_name,
       template_body: cf_template_body,
       parameters: build_params,
       capabilities: CAPABILITIES,
       tags: tags}
    end

    def stack_name
      "#{@group["cluster_name"]}-Workers-#{@group["group_name"]}"
    end

    def build_params
      @group["bootstrap_args"] = bootstrap_args
      @group["ami"] ||= default_ami
      @group.except("taints").inject([]) do |params, (k, v)|
        params << build_param(k, v)
      end
    end

    def bootstrap_args
      flags = "--node-labels=kubernetes.io/role=node,eks/node-group=#{@group["group_name"].downcase}"
      if taints = @group["taints"]
        flags = "#{flags} --register-with-taints=#{taints}"
      end
      "--kubelet-extra-args \"#{flags}\"" 
    end

    def add_bootstrap_args(group)
      group["bootstrap_args"] = base
      group.except("taints")
    end

    def build_param(k, v)
      {parameter_key: T[k.to_sym],
       parameter_value: v.to_s}
    end

    def default_ami
      if gpu?
        GPU_AMIS[config["region"]]
      else
        AMIS[config["region"]]
      end
    end

    def gpu?
      @group["instance_type"].start_with?("p2.") || @group["instance_type"].start_with?("p3.")
    end

    def config
      Config[@cluster_name]
    end

  end

end
