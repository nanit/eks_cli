require 'json'
require_relative 'log'
require 'active_support/core_ext/hash'
require 'fileutils'
require 'aws-sdk-s3'
module EksCli
  class Config

    AZS = {"us-east-1" => ["us-east-1a", "us-east-1b", "us-east-1c"],
           "us-west-2" => ["us-west-2a", "us-west-2b", "us-west-2c"],
           "us-east-2" => ["us-east-2a", "us-east-2b", "us-east-2c"],
           "us-west-1" => ["us-west-1b", "us-west-1b", "us-west-1c"]}

    class << self

      def [](cluster_name)
        new(cluster_name)
      end

      def s3_bucket=(bucket)
        @s3_bucket = bucket
      end

      def s3_bucket
        @s3_bucket || raise("no s3 bucket set")
      end
    end

    def initialize(cluster_name)
      @cluster_name = cluster_name
    end

    def delete
      Log.info "deleting configuration for #{@cluster_name} at #{dir}"
      s3.delete_object(bucket: s3_bucket, key: config_path)
      s3.delete_object(bucket: s3_bucket, key: state_path)
      s3.delete_object(bucket: s3_bucket, key: groups_path)
      s3.delete_object(bucket: s3_bucket, key: dir)
    end

    def read_from_disk
      base = read(config_path)
      base["cluster_name"] = @cluster_name
      base = base.merge(read(state_path)).merge(read(groups_path))
      base
    end

    def [](k)
      read_from_disk[k]
    end

    def for_group(group_name)
      all = read_from_disk
      group = all["groups"][group_name]
        .merge(all.slice("cluster_name", "control_plane_sg_id", "nodes_sg_id", "vpc_id"))
      group["subnets"] = group["subnets"].map {|s| all["subnets"][s-1]}.join(",")
      group
    end

    def write(attrs, to = :state)
      path = resolve_config_file(to)
      current = read(path) rescue {}
      Log.info "updating configuration file #{path}:\n#{attrs}"
      attrs = attrs.inject({}) {|h,(k,v)| h[k.to_s] = v; h}
      updated = current.deep_merge(attrs)
      write_to_file(updated, path)
    end

    def bootstrap(attrs)
      write_to_file(attrs, config_path)
      write_to_file({}, state_path)
      write_to_file({}, groups_path)
      Log.info "written configuration files to:\n#{config_path}\n#{state_path}\n#{groups_path}"
    end

    def set_iam_policies(policies)
      write({iam_policies: policies}, :groups)
    end

    def update_nodegroup(options)
      options = options.slice("ami", "group_name", "instance_type", "subnets", "ssh_key_name", "volume_size", "taints", "min", "max", "enable_docker_bridge", "desired", "spotinst")
      raise "bad nodegroup name #{options["group_name"]}" if options["group_name"] == nil || options["group_name"].empty?
      write({groups: { options["group_name"] => options }}, :groups)
    end
    
    def add_user(arn, username, groups)
      write({"users" => {arn => {"username" => username, "groups" => groups}}})
    end

    private

    def resolve_config_file(sym)
      case sym
      when :state
        state_path
      when :config
        config_path
      when :groups
        groups_path
      else raise "no such config #{sym}"
      end
    end

    def write_to_file(attrs, path)
      s3.put_object(bucket: s3_bucket, key: path, body: attrs.to_json)
    end

    def read(path)
      resp = s3.get_object(bucket: s3_bucket, key: path)
      body = resp.body.read
      JSON.parse(body)
    end

    def groups_path
      "#{dir}/groups.json"
    end

    def state_path
      "#{dir}/state.json"
    end

    def config_path
      "#{dir}/config.json"
    end

    def dir
      "eks-cli/#{@cluster_name}"
    end

    def s3_bucket
      self.class.s3_bucket
    end

    def s3
      @s3 ||= Aws::S3::Client.new
    end

  end
end
