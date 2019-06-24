# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'eks_cli/version'

Gem::Specification.new do |s|
  s.name        = 'eks_cli'
  s.version     = EksCli::VERSION
  s.date        = '2018-11-18'
  s.summary     = "Make EKS great again!"
  s.description = "A utility to manage and create EKS (Kubernetes) cluster on Amazon Web Services"
  s.authors     = ["Erez Rabih"]
  s.email       = 'erez.rabih@gmail.com'
  s.homepage    =
    'https://github.com/nanit/eks_cli'
  s.license       = 'MIT'
  s.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  s.bindir        = "bin"
  s.executables   = ["eks"]
  s.require_paths = ["lib"]
  s.add_dependency 'aws-sdk-s3', '~> 1'
  s.add_dependency 'thor', '0.20.3'
  s.add_dependency 'aws-sdk-ec2', '1.62.0'
  s.add_dependency 'aws-sdk-cloudformation', '1.13.0'
  s.add_dependency 'aws-sdk-route53', '1.16.0'
  s.add_dependency 'aws-sdk-autoscaling','1.13.0'
  s.add_dependency 'activesupport', '5.2.1.1'
  s.add_dependency 'kubeclient', '4.1.0'
  s.add_dependency 'httparty', '0.16.3'
  s.add_dependency 'ipaddress', '0.8.3'
end

