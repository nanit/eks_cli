require 'aws-sdk-ec2'
require 'config'
require 'log'

module EksCli
  module VPC
    class Client
      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def set_inter_vpc_networking(old_vpc_id, old_vpc_sg_id)
        @old_vpc = vpc_by_id(old_vpc_id)
        Log.info "setting vpc networking between #{new_vpc.id} and #{old_vpc.id}"
        peering_connection_id = create_vpc_peering_connection
        update_route_tables(peering_connection_id)
        allow_networking(old_vpc_sg_id, peering_connection_id)
      end

      def create_vpc_peering_connection
        Log.info "creating VPC peering request between #{new_vpc.id} and #{old_vpc.id}"
        pcr = client.create_vpc_peering_connection({
          dry_run: false,
          peer_vpc_id: old_vpc.id,
          vpc_id: new_vpc.id,
        })
        Log.info "created peering request #{pcr}"
        peering_connection_id = pcr.vpc_peering_connection.vpc_peering_connection_id
        Log.info "accepting peering request"
        res = client.accept_vpc_peering_connection({
          dry_run: false,
          vpc_peering_connection_id: peering_connection_id,
        })
        Log.info "request accepted: #{res}"
        return peering_connection_id
      end

      def update_route_tables(peering_connection_id)
        Log.info "updating route tables"
        point_from(old_vpc, new_vpc, peering_connection_id)
        point_from(new_vpc, old_vpc, peering_connection_id)
        Log.info "done updating route tables"
      end

      def allow_networking(old_vpc_sg_id, peering_connection_id)
        Log.info "allowing incoming traffic to sg #{old_vpc_sg_id} from #{config["nodes_sg_id"]} on vpc #{new_vpc.id}"
        old_sg  = Aws::EC2::SecurityGroup.new(old_vpc_sg_id, client: client)
        res = old_sg.authorize_ingress(
          ip_permissions: [
            {
              from_port: "-1",
              ip_protocol: "-1",
              to_port: "-1",
              user_id_group_pairs: [
                {
                  description: "Accept all traffic from nodes on EKS cluster #{@cluster_name}",
                  group_id: config["nodes_sg_id"],
                  vpc_id: new_vpc.id,
                  vpc_peering_connection_id: peering_connection_id,
                },
              ],
            },
          ]
        )
        Log.info "done setting networking (#{res})"
      end

      def point_from(from_vpc, to_vpc, peering_connection_id)
        Log.info "pointing from #{from_vpc.id} to #{to_vpc.id} via #{peering_connection_id}"
        from_vpc.route_tables.each do |rt|
          res = client.create_route({
            destination_cidr_block: to_vpc.cidr_block, 
            gateway_id: peering_connection_id, 
            route_table_id: rt.id, 
          })
          Log.info "set route #{res}"
        end

      end

      def new_vpc
        @new_vpc ||= vpc_by_id(new_vpc_id)
      end

      def old_vpc
        @old_vpc
      end

      def vpc_by_id(id)
        Aws::EC2::Vpc.new(id, client: client)
      end

      def config
        @config ||= Config[@cluster_name]
      end

      def client
        @client ||= Aws::EC2::Client.new(region: config["region"])
      end

      def new_vpc_id
        @new_vpc_id ||= config["vpc_id"]
      end

      def old_vpc_id
        @old_vpc_id
      end

    end
  end

end
