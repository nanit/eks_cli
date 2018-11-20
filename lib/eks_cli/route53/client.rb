require 'aws-sdk-route53'
require 'log'
require 'config'
require 'k8s/client'
module EksCli
  module Route53
    class Client

      def initialize(cluster_name)
        @cluster_name = cluster_name
      end

      def update_dns(hostname, k8s_service_name, k8s_ns, route53_hosted_zone_id, elb_hosted_zone_id)
        change_dns_target(hostname, k8s.get_elb(k8s_service_name, k8s_ns), route53_hosted_zone_id, elb_hosted_zone_id)
      end

      private

      def k8s
        @k8s ||= K8s::Client.new(@cluster_name)
      end

      def change_dns_target(route53_host, elb_host, route53_hosted_zone_id, elb_hosted_zone_id)
        Log.info "Setting Route53 record #{route53_host} --> #{elb_host}"
        resp = client.change_resource_record_sets({
          change_batch: {
            changes: [
              {
                action: "UPSERT", 
                resource_record_set: {
                  name: route53_host, 
                  type: "A", 
                  alias_target: {
                    dns_name: elb_host, 
                    evaluate_target_health: false, 
                    hosted_zone_id: elb_hosted_zone_id, 
                  }, 
                }, 
              }, 
            ], 
          }, 
          hosted_zone_id: route53_hosted_zone_id, 
        })
        Log.info "Done: #{resp}"
      end

      def config
        @config ||= Config[@cluster_name]
      end

      def elb_hosted_zone_id
        config["elb_hosted_zone_id"]
      end

      def route53_hosted_zone_id
        config["route53_hosted_zone_id"]
      end

      def client
        @client ||= Aws::Route53::Client.new(region: config["region"])
      end


    end
  end

end
