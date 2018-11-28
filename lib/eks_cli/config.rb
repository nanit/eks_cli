require 'json'
require_relative 'log'
require 'active_support/core_ext/hash'
require 'fileutils'
module EksCli
  class Config
    class << self
      def [](cluster_name)
        new(cluster_name)
      end

    end

    def initialize(cluster_name)
      @cluster_name = cluster_name
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
      group = group_defaults
        .merge(all["groups"][group_name])
        .merge(all.slice("cluster_name", "control_plane_sg_id", "nodes_sg_id", "vpc_id"))
      group["subnets"] = all["subnets"][0..(group["num_subnets"]-1)].join(",")
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
      options = options.slice("ami", "group_name", "instance_type", "num_subnets", "ssh_key_name", "taints", "min", "max")
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
      File.open(path, 'w') {|file| file.write(attrs.to_json)}
    end

    def read(path)
      f = File.read(path)
      JSON.parse(f)
    end

    def groups_path
      with_config_dir { |dir| "#{dir}/groups.json" }
    end

    def state_path
      with_config_dir { |dir| "#{dir}/state.json" }
    end

    def config_path
      with_config_dir { |dir| "#{dir}/config.json" }
    end

    def dir
      "#{ENV['HOME']}/.eks/#{@cluster_name}"
    end

    def with_config_dir
      FileUtils.mkdir_p(dir)
      yield dir
    end

    def group_defaults
      {"group_name" => "Workers",
       "instance_type" => "m5.xlarge",
       "max" => 1,
       "min" =>  1,
       "num_subnets" =>  3,
       "volume_size" => 100}
    end
  end
end
