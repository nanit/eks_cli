# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |s|
  s.name        = 'eks_cli'
  s.version     = '0.1.0'
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
  s.add_dependency 'thor'
  s.add_dependency 'aws-sdk-iam'
  s.add_dependency 'aws-sdk-eks'
  s.add_dependency 'aws-sdk-ec2'
  s.add_dependency 'aws-sdk-cloudformation'
  s.add_dependency 'aws-sdk-route53'
  s.add_dependency 'activesupport'
  s.add_dependency 'kubeclient'
end

