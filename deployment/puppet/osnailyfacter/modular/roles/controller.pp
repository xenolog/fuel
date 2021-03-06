notice('MODULAR: controller.pp')

# Pulling hiera
$public_vip                     = hiera('public_vip')
$management_vip                 = hiera('management_vip')
$internal_address               = hiera('internal_address')
$primary_controller             = hiera('primary_controller')
$storage_address                = hiera('storage_address')
$use_neutron                    = hiera('use_neutron')
$neutron_nsx_config             = hiera('nsx_plugin')
$cinder_nodes_array             = hiera('cinder_nodes', [])
$sahara_hash                    = hiera('sahara', {})
$murano_hash                    = hiera('murano', {})
$heat_hash                      = hiera('heat', {})
$verbose                        = true
$debug                          = hiera('debug', true)
$use_monit                      = false
$mongo_hash                     = hiera('mongo', {})
$auto_assign_floating_ip        = hiera('auto_assign_floating_ip', false)
$nodes_hash                     = hiera('nodes', {})
$storage_hash                   = hiera('storage', {})
$vcenter_hash                   = hiera('vcenter', {})
$nova_hash                      = hiera('nova', {})
$mysql_hash                     = hiera('mysql', {})
$rabbit_hash                    = hiera('rabbit', {})
$glance_hash                    = hiera('glance', {})
$keystone_hash                  = hiera('keystone', {})
$cinder_hash                    = hiera('cinder', {})
$ceilometer_hash                = hiera('ceilometer',{})
$access_hash                    = hiera('access', {})
$controllers                    = hiera('controllers')
$neutron_mellanox               = hiera('neutron_mellanox', false)
$syslog_hash                    = hiera('syslog', {})
$base_syslog_hash               = hiera('base_syslog', {})
$use_syslog                     = hiera('use_syslog', true)
$syslog_log_facility_glance     = hiera('syslog_log_facility_glance', 'LOG_LOCAL2')
$syslog_log_facility_cinder     = hiera('syslog_log_facility_cinder', 'LOG_LOCAL3')
$syslog_log_facility_neutron    = hiera('syslog_log_facility_neutron', 'LOG_LOCAL4')
$syslog_log_facility_nova       = hiera('syslog_log_facility_nova','LOG_LOCAL6')
$syslog_log_facility_keystone   = hiera('syslog_log_facility_keystone', 'LOG_LOCAL7')
$syslog_log_facility_murano     = hiera('syslog_log_facility_murano', 'LOG_LOCAL0')
$syslog_log_facility_heat       = hiera('syslog_log_facility_heat','LOG_LOCAL0')
$syslog_log_facility_sahara     = hiera('syslog_log_facility_sahara','LOG_LOCAL0')
$syslog_log_facility_ceilometer = hiera('syslog_log_facility_ceilometer','LOG_LOCAL0')
$syslog_log_facility_ceph       = hiera('syslog_log_facility_ceph','LOG_LOCAL0')
$nova_service_down_time         = hiera('nova_service_down_time')
$nova_report_interval           = hiera('nova_report_interval')

# TODO: openstack_version is confusing, there's such string var in hiera and hardcoded hash
$hiera_openstack_version = hiera('openstack_version')
$openstack_version = {
  'keystone'   => 'installed',
  'glance'     => 'installed',
  'horizon'    => 'installed',
  'nova'       => 'installed',
  'novncproxy' => 'installed',
  'cinder'     => 'installed',
}

# Do the stuff
if $neutron_mellanox {
  $mellanox_mode = $neutron_mellanox['plugin']
} else {
  $mellanox_mode = 'disabled'
}

if (!empty(filter_nodes(hiera('nodes'), 'role', 'ceph-osd')) or
  $storage_hash['volumes_ceph'] or
  $storage_hash['images_ceph'] or
  $storage_hash['objects_ceph']
) {
  $use_ceph = true
} else {
  $use_ceph = false
}

if $use_neutron {
  include l23network::l2
  $novanetwork_params        = {}
  $neutron_config            = hiera('quantum_settings')
  $network_provider          = 'neutron'
  $neutron_db_password       = $neutron_config['database']['passwd']
  $neutron_user_password     = $neutron_config['keystone']['admin_password']
  $neutron_metadata_proxy_secret = $neutron_config['metadata']['metadata_proxy_shared_secret']
  $base_mac                  = $neutron_config['L2']['base_mac']
  if $neutron_nsx_config['metadata']['enabled'] {
    $use_vmware_nsx     = true
  }
} else {
  $neutron_config     = {}
  $novanetwork_params = hiera('novanetwork_parameters')
  $network_size       = $novanetwork_params['network_size']
  $num_networks       = $novanetwork_params['num_networks']
  $vlan_start         = $novanetwork_params['vlan_start']
  $network_provider   = 'nova'
}
$network_manager = "nova.network.manager.${novanetwork_params['network_manager']}"

if !$ceilometer_hash {
  $ceilometer_hash = {
    enabled => false,
    db_password => 'ceilometer',
    user_password => 'ceilometer',
    metering_secret => 'ceilometer',
  }
  $ext_mongo = false
} else {
  # External mongo integration
  if $mongo_hash['enabled'] {
    $ext_mongo_hash = hiera('external_mongo')
    $ceilometer_db_user = $ext_mongo_hash['mongo_user']
    $ceilometer_db_password = $ext_mongo_hash['mongo_password']
    $ceilometer_db_name = $ext_mongo_hash['mongo_db_name']
    $ext_mongo = true
  } else {
    $ceilometer_db_user = 'ceilometer'
    $ceilometer_db_password = $ceilometer_hash['db_password']
    $ceilometer_db_name = 'ceilometer'
    $ext_mongo = false
    $ext_mongo_hash = {}
  }
}


if $primary_controller {
  if ($mellanox_mode == 'ethernet') {
    $test_vm_pkg = 'cirros-testvm-mellanox'
  } else {
    $test_vm_pkg = 'cirros-testvm'
  }
  package { 'cirros-testvm' :
    ensure => 'installed',
    name   => $test_vm_pkg,
  }
}


if $ceilometer_hash['enabled'] {
  if $ext_mongo {
    $mongo_hosts = $ext_mongo_hash['hosts_ip']
    if $ext_mongo_hash['mongo_replset'] {
      $mongo_replicaset = $ext_mongo_hash['mongo_replset']
    } else {
      $mongo_replicaset = undef
    }
  } else {
    $mongo_hosts = mongo_hosts($nodes_hash)
    if size(mongo_hosts($nodes_hash, 'array', 'mongo')) > 1 {
      $mongo_replicaset = 'ceilometer'
    } else {
      $mongo_replicaset = undef
    }
  }
}

if !$rabbit_hash['user'] {
  $rabbit_hash['user'] = 'nova'
}

if ! $use_neutron {
  $floating_ips_range = hiera('floating_network_range')
}
$floating_hash = {}

##CALCULATED PARAMETERS


##NO NEED TO CHANGE

$node = filter_nodes($nodes_hash, 'name', $::hostname)
if empty($node) {
  fail("Node $::hostname is not defined in the hash structure")
}

# get cidr netmasks for VIPs
$primary_controller_nodes = filter_nodes($nodes_hash,'role','primary-controller')

##REFACTORING NEEDED


##TODO: simply parse nodes array
$controller_internal_addresses = nodes_to_hash($controllers,'name','internal_address')
$controller_public_addresses = nodes_to_hash($controllers,'name','public_address')
$controller_storage_addresses = nodes_to_hash($controllers,'name','storage_address')
$controller_hostnames = keys($controller_internal_addresses)
$controller_nodes = ipsort(values($controller_internal_addresses))
$controller_node_public  = $public_vip
$controller_node_address = $management_vip
$roles = node_roles($nodes_hash, hiera('uid'))

# AMQP client configuration
if $internal_address in $controller_nodes {
  # prefer local MQ broker if it exists on this node
  $amqp_nodes = concat(['127.0.0.1'], fqdn_rotate(delete($controller_nodes, $internal_address)))
} else {
  $amqp_nodes = fqdn_rotate($controller_nodes)
}

$amqp_port = '5673'
$amqp_hosts = inline_template("<%= @amqp_nodes.map {|x| x + ':' + @amqp_port}.join ',' %>")
$rabbit_ha_queues = true

# RabbitMQ server configuration
$rabbitmq_bind_ip_address = 'UNSET'              # bind RabbitMQ to 0.0.0.0
$rabbitmq_bind_port = $amqp_port
$rabbitmq_cluster_nodes = $controller_hostnames  # has to be hostnames

# SQLAlchemy backend configuration
$max_pool_size = min($::processorcount * 5 + 0, 30 + 0)
$max_overflow = min($::processorcount * 5 + 0, 60 + 0)
$max_retries = '-1'
$idle_timeout = '3600'

$cinder_iscsi_bind_addr = $storage_address

# Determine who should get the volume service

if (member($roles, 'cinder') and $storage_hash['volumes_lvm']) {
  $manage_volumes = 'iscsi'
} elsif (member($roles, 'cinder') and $storage_hash['volumes_vmdk']) {
  $manage_volumes = 'vmdk'
} elsif ($storage_hash['volumes_ceph']) {
  $manage_volumes = 'ceph'
} else {
  $manage_volumes = false
}

# Determine who should be the default backend

if ($storage_hash['images_ceph']) {
  $glance_backend = 'ceph'
  $glance_known_stores = [ 'glance.store.rbd.Store', 'glance.store.http.Store' ]
} elsif ($storage_hash['images_vcenter']) {
  $glance_backend = 'vmware'
  $glance_known_stores = [ 'glance.store.vmware_datastore.Store', 'glance.store.http.Store' ]
} else {
  $glance_backend = 'swift'
  $glance_known_stores = [ 'glance.store.swift.Store', 'glance.store.http.Store' ]
}

$network_config = {
  'vlan_start'     => $vlan_start,
}

# NOTE(bogdando) for controller nodes running Corosync with Pacemaker
#   we delegate all of the monitor functions to RA instead of monit.
if member($roles, 'controller') or member($roles, 'primary-controller') {
  $use_monit_real = false
} else {
  $use_monit_real = $use_monit
}

if $use_monit_real {
  # Configure service names for monit watchdogs and 'service' system path
  # FIXME(bogdando) replace service_path to systemd, once supported
  include nova::params
  include cinder::params
  include neutron::params
  include l23network::params
  $nova_compute_name   = $::nova::params::compute_service_name
  $nova_api_name       = $::nova::params::api_service_name
  $nova_network_name   = $::nova::params::network_service_name
  $cinder_volume_name  = $::cinder::params::volume_service
  $ovs_vswitchd_name   = $::l23network::params::ovs_service_name
  case $::osfamily {
    'RedHat' : {
       $service_path   = '/sbin/service'
    }
    'Debian' : {
      $service_path    = '/usr/sbin/service'
    }
    default  : {
      fail("Unsupported osfamily: ${osfamily} for os ${operatingsystem}")
    }
  }
}

#HARDCODED PARAMETERS

$mirror_type = 'external'
Exec { logoutput => true }

if $use_vmware_nsx {
  class { 'plugin_neutronnsx':
    neutron_config     => $neutron_config,
    neutron_nsx_config => $neutron_nsx_config,
    roles              => $roles,
  }
}

#################################################################
include osnailyfacter::test_controller

nova_config {
  'DEFAULT/teardown_unused_network_gateway': value => 'True'
}

#ADDONS START

if $sahara_hash['enabled'] {
  $scheduler_default_filters = [ 'DifferentHostFilter' ]
} else {
  $scheduler_default_filters = []
}

class { '::nova::scheduler::filter':
  cpu_allocation_ratio       => '8.0',
  disk_allocation_ratio      => '1.0',
  ram_allocation_ratio       => '1.0',
  scheduler_host_subset_size => '30',
  scheduler_default_filters  => concat($scheduler_default_filters, [ 'RetryFilter', 'AvailabilityZoneFilter', 'RamFilter', 'CoreFilter', 'DiskFilter', 'ComputeFilter', 'ComputeCapabilitiesFilter', 'ImagePropertiesFilter', 'ServerGroupAntiAffinityFilter', 'ServerGroupAffinityFilter' ])
}

# From logasy filter.pp
nova_config {
  'DEFAULT/ram_weight_multiplier':        value => '1.0'
}

if ($::mellanox_mode == 'ethernet') {
  $ml2_eswitch = $neutron_mellanox['ml2_eswitch']
  class { 'mellanox_openstack::controller':
    eswitch_vnic_type            => $ml2_eswitch['vnic_type'],
    eswitch_apply_profile_patch  => $ml2_eswitch['apply_profile_patch'],
  }
}

#ADDONS END

########################################################################

# TODO(bogdando) add monit zabbix services monitoring, if required
# NOTE(bogdando) for nodes with pacemaker, we should use OCF instead of monit

# BP https://blueprints.launchpad.net/mos/+spec/include-openstackclient
package { 'python-openstackclient' :
  ensure => installed,
}

# Reduce swapiness on controllers, see LP#1413702
sysctl::value { 'vm.swappiness':
  value => "10"
}

# Stubs
class mysql::server {}
include mysql::server

# vim: set ts=2 sw=2 et :
