require 'active_support/core_ext/hash'
require 'aws-sdk-autoscaling'
require 'config'
require 'spotinst/client'
require 'cloudformation/stack'
require 'k8s/auth'
require 'log'

module EksCli
  class NodeGroup

    T = {cluster_name: "ClusterName",
         control_plane_sg_id: "ClusterControlPlaneSecurityGroup",
         nodes_sg_id: "ClusterSecurityGroup",
         min: "NodeAutoScalingGroupMinSize",
         max: "NodeAutoScalingGroupMaxSize",
         desired: "NodeAutoScalingGroupDesiredCapacity",
         instance_type: "NodeInstanceType",
         ami: "NodeImageId",
         volume_size: "NodeVolumeSize",
         ssh_key_name: "KeyName",
         vpc_id: "VpcId",
         subnets: "Subnets",
         group_name: "NodeGroupName",
         iam_policies: "NodeGroupIAMPolicies",
         bootstrap_args: "BootstrapArguments"}

    AMIS = {"1.12" => {"us-west-2" => "ami-0923e4b35a30a5f53",
                       "us-east-1" => "ami-0abcb9f9190e867ab",
                       "us-east-2" => "ami-04ea7cb66af82ae4a",
                       "us-west-1" => "ami-03612357ac9da2c7d"},
            "1.13" => {"us-west-2" => "ami-089d3b6350c1769a6",
                       "us-east-1" => "ami-08c4955bcc43b124e",
                       "us-east-2" => "ami-07ebcae043cf995aa"}}

    GPU_AMIS = {"1.12" => {"us-west-2" => "ami-0bebf2322fd52a42e",
                           "us-east-1" => "ami-0cb7959f92429410a",
                           "us-east-2" => "ami-0118b61dc2312dee2",
                           "us-west-1" => "ami-047637529a86c7237"},
                "1.13" => {"us-west-2" => "ami-08e5329e1dbf22c6a",
                           "us-east-1" => "ami-02af865c0f3b337f2",
                           "us-east-2" => "ami-01f82bb66c17faf20"}}

    EKS_IAM_POLICIES = %w{AmazonEKSWorkerNodePolicy
                          AmazonEKS_CNI_Policy
                          AmazonEC2ContainerRegistryReadOnly}

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

    def name; @name; end

    def tags
      [{key: "eks-nodegroup", value: @group["group_name"]},
       {key: "eks-cluster", value: @cluster_name}]
    end

    def delete
      Log.info "deleting nodegroup #{@name}"
      cf_stack.delete
      if @group["spotinst"]
        spotinst.delete_elastigroup(@group["spotinst"]["id"])
      end
    end

    def asg
      @asg ||= cf_stack.resource("NodeGroup")
    end

    def instance_type
      @group["instance_type"]
    end

    def export_to_spotinst(exact_instance_type)
      Log.info "exporting nodegroup #{@name} to spotinst"
      instance_types = exact_instance_type ? [instance_type] : nil
      response = spotinst.import_asg(config["region"], asg, instance_types)
      if response.code == 200
        Log.info "Successfully created elastigroup"
        elastigroup = response.parsed_response["response"]["items"].first
        config.update_nodegroup({"group_name" => @name, "spotinst" => elastigroup})
      else
        Log.warn "Error creating elastigroup:\n #{response}"
      end
    end

    def cf_stack
      CloudFormation::Stack.find(@cluster_name, stack_name)
    rescue Aws::CloudFormation::Errors::ValidationError => e
      Log.error("could not find stack for nodegroup #{@name} - please make sure to run eks create-nodegroup --all --yes -c <cluster_name> to sync config")
      raise e
    end

    def scale(min, max, asg = true, spotinst = false)
      scale_asg(min, max) if asg
      scale_spotinst(min, max) if spotinst
    end

    private

    def scale_spotinst(min, max)
      if eid = @group.dig("spotinst", "id")
        spotinst.scale(eid, min, max)
      else
        Log.warn "could not find spotinst elastigroup for nodegroup #{@name}"
      end
    end

    def scale_asg(min, max)
      Log.info "scaling ASG #{asg}: min -> #{min}, max -> #{max}"
      Log.info asg_client.update_auto_scaling_group({
        auto_scaling_group_name: asg, 
        max_size: max, 
        min_size: min
      })

    end

    def cf_template_body
      @cf_template_body ||= File.read(File.join($root_dir, '/assets/cf/nodegroup.yaml'))
    end

    def await(stack)

      while stack.pending? do
        Log.info "waiting for stack #{stack.id} - status is #{stack.status}"
        sleep 10
      end

      Log.info "stack completed with status #{stack.status}"

      K8s::Auth.new(@cluster_name).update
    end

    def cloudformation_config
      {stack_name: stack_name,
       template_body: cf_template_body,
       parameters: build_params,
       capabilities: CAPABILITIES,
       tags: tags}
    end

    def stack_name
      "#{@group["cluster_name"]}-NodeGroup-#{@group["group_name"]}"
    end

    def build_params
      @group["bootstrap_args"] = bootstrap_args
      @group["ami"] ||= default_ami
      @group["iam_policies"] = iam_policies
      @group.inject([]) do |params, (k, v)|
        if param = build_param(k, v)
          params << param
        else
          params
        end
      end
    end

    def iam_policies
      (EKS_IAM_POLICIES + (config["iam_policies"] || [])).map {|p| "arn:aws:iam::aws:policy/#{p}"}.join(",")
    end

    def bootstrap_args
      kubelet_flags = "--node-labels=kubernetes.io/role=node,eks/node-group=#{@group["group_name"].downcase}"
      if taints = @group["taints"]
        kubelet_flags = "#{kubelet_flags} --register-with-taints=#{taints}"
      end
      flags = "--kubelet-extra-args \"#{kubelet_flags}\"" 
      flags = "#{flags} --enable-docker-bridge true" if @group["enable_docker_bridge"]
      flags
    end

    def add_bootstrap_args(group)
      group["bootstrap_args"] = base
      group.except("taints")
    end

    def build_param(k, v)
      if key = T[k.to_sym]
        {parameter_key: key,
         parameter_value: v.to_s}
      end
    end

    def default_ami
      if gpu?
        GPU_AMIS[config["kubernetes_version"]][config["region"]]
      else
        AMIS[config["kubernetes_version"]][config["region"]]
      end
    end

    def gpu?
      @group["instance_type"].start_with?("p2.") || @group["instance_type"].start_with?("p3.")
    end

    def config
      Config[@cluster_name]
    end

    def asg_client
      @asg_client ||= Aws::AutoScaling::Client.new(region: config["region"])
    end

    def spotinst
      @spotinst ||= Spotinst::Client.new
    end

  end

end
