require 'aws-sdk-ec2'
require 'log'
require 'config'
module EC2
  class SecurityGroup

    def initialize(cluster_name, open_ports)
      @cluster_name = cluster_name
      @open_ports = open_ports
    end

    def create
      Log.info "creating security group for in-cluster communication for #{@cluster_name}"
      gid = client.create_security_group(description: "Security group for in-cluster communication on #{@cluster_name}", 
                                         group_name: "#{@cluster_name}-SG", 
                                         vpc_id: vpc_id).group_id

      Log.info "created security group #{gid}, setting ingress/egress rules"

      client.authorize_security_group_ingress(group_id: gid,
                                              ip_permissions: [{from_port: -1,
                                                                ip_protocol: "-1",
                                                                to_port: -1,
                                                                user_id_group_pairs: [{description: "in-cluster communication for #{@cluster_name}", 
                                                                                       group_id: gid}]}])

      @open_ports.each do |port|

        client.authorize_security_group_ingress(group_id: gid,
                                                ip_permissions: [{from_port: port,
                                                                  to_port: port,
                                                                  ip_protocol: "tcp",
                                                                  ip_ranges: [{cidr_ip: "0.0.0.0/0",
                                                                               description: "EKS cluster allow access on port #{port}"}]}])
      end

      Log.info "done"
      gid
    end

    private

    def vpc_id
      Config[@cluster_name]["vpc_id"]
    end

    def client
      @client ||= Aws::EC2::Client.new(region: Config[@cluster_name]["region"])
    end
  end
end
