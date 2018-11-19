$root_dir = File.expand_path(File.dirname(path = File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__))
helpers_dir = "#{$root_dir}/eks_cli"
$LOAD_PATH.unshift(helpers_dir) unless $LOAD_PATH.include?(helpers_dir)

require 'cli'
