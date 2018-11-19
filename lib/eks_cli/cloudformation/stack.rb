require 'cloudformation/client'
require 'log'

module EksCli
  module CloudFormation
    class Stack

      def self.create(cluster_name, config)
        Log.info "creating cloudformation stack #{config[:stack_name]}"
        begin
          stack_id = client(cluster_name).create_stack(config).stack_id
        rescue Aws::CloudFormation::Errors::AlreadyExistsException => e
          Log.warn "stack #{config[:stack_name]} already exists"
          stack_id = Aws::CloudFormation::Stack.new(config[:stack_name], client: client(cluster_name)).stack_id
        end
        new(cluster_name, stack_id)
      end

      def self.await(stacks)
        while pending(stacks) > 0 do
          Log.info "#{pending(stacks)} stacks out of #{stacks.count} are still being created"
          sleep 10
        end
        stacks
      end

      def self.find(cluster_name, name)
        new(cluster_name, Aws::CloudFormation::Stack.new(name, client: client(cluster_name)).stack_id)
      end

      def initialize(cluster_name, stack_id)
        @cluster_name = cluster_name
        @id = stack_id
      end

      def delete
        Log.info "deleting stack #{id} from cloudformation"
        client.delete_stack(stack_name: id)
      end

      def id; @id; end

      def pending?
        status == "CREATE_IN_PROGRESS"
      end

      def eks_worker?
        !worker_tag.empty?
      end

      def node_instance_role_arn
        output("NodeInstanceRole")
      end

      def node_instance_role_name
        node_instance_role_arn.split("/")[1]
      end

      def status
        stack(reload: true).stack_status
      end

      def reload
        stack(reload: true)
        self
      end

      def output(key)
        stack.outputs.select {|a| a.output_key == key}.first.output_value
      end

      def outputs
        stack.outputs
      end

      private

      def self.pending(stacks)
        stacks.select(&:pending?).count
      end

      def self.client(cluster_name)
        CloudFormation::Client.get(cluster_name)
      end

      def client
        self.class.client(@cluster_name)
      end

      def stack(reload: false)
        if reload
          @stack = fetch
        else
          @stack ||= fetch
        end
      end
      
      def fetch
        client.describe_stacks(stack_name: @id).stacks.first
      end

      def worker_tag
        stack.tags.select {|t| worker_tag?(t)}
      end

      def worker_tag?(tag)
        tag.key == "eks-nodegroup"
      end

    end

  end
end
