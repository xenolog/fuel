class puppetmaster::params {
  
	case $::osfamily {
	    'RedHat': {
         $puppet_master_version  = "2.7.19-1.el6"
         $puppet_master_packages = "puppet-server" 
         $mongrel_packages = "rubygem-mongrel"
         $daemon_config_file = "/etc/sysconfig/puppetmaster"    
         $daemon_config_template = "puppetmaster/sysconfig_puppetmaster.erb"
      }
      'Debian': {
         $puppet_master_version  = "2.7.19-1puppetlabs1"
         $puppet_master_packages = ["puppetmaster", "puppetmaster-common", "puppet-common"]
         $mongrel_packages = "mongrel"
         $daemon_config_file = "/etc/default/puppetmaster"
         $daemon_config_template = "puppetmaster/default_puppetmaster.erb"
      }
      default: {
        fail("Unsupported osfamily: ${::osfamily} operatingsystem: ${::operatingsystem}, module ${module_name} only support osfamily RedHat and Debian")
      }
  } 
	  
	 
	case $::osfamily {
	    'RedHat': {
	       $mysql_packages = ['mysql',  'mysql-server', 'mysql-devel', 'rubygems', 'ruby-devel',  'make',  'gcc']      
	    }
	    'Debian': {
	       $mysql_packages = ['mysql-server', 'libmysql-ruby', 'rubygems', 'make',  'gcc']  
	    }
	    default: {
	      fail("Unsupported osfamily: ${::osfamily} operatingsystem: ${::operatingsystem}, module ${module_name} only support osfamily RedHat and Debian")
	    }
	}
  
}