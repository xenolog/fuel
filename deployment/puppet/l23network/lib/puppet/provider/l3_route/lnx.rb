require 'ipaddr'
require 'yaml'

Puppet::Type.type(:l3_route).provide(:lnx) do
  defaultfor :osfamily => :linux
  commands   :iproute => 'ip'


  def self.prefetch(resources)
    interfaces = instances
    resources.keys.each do |name|
      if provider = interfaces.find{ |ii| ii.name == name }
        resources[name].provider = provider
      end
    end
  end

  def self.get_routes
    # return array of hashes -- all defined routes.
    rv = []
    File.open('/proc/net/route').readlines.reject{|l| l.match(/^[Ii]face.+/) or l.match(/^(\r\n|\n|\s*)$|^$/)}.map{|l| l.split(/\s+/)}.each do |line|
      #https://github.com/kwilczynski/facter-facts/blob/master/default_gateway.rb
      iface = line[0]
      metric = line[6]
      # whether gateway is default
      if line[1] == '00000000'
        destination = 'default'
        destination_addr = nil
        mask = nil
        route_type = 'default'
      else
        destination_addr = [line[1]].pack('H*').unpack('C4').reverse.join('.')
        mask = [line[7]].pack('H*').unpack('B*')[0].count('1')
        destination = "#{destination_addr}/#{mask}"
      end
      # whether route is local
      if line[2] == '00000000'
        gateway = nil
        route_type = 'local'
      else
        gateway = [line[2]].pack('H*').unpack('C4').reverse.join('.')
        route_type = nil
      end
      rv << {
        :network        => destination,
        :gateway        => gateway,
        :metric         => metric.to_i,
        :type           => route_type,
        :interface      => iface,
      }
    end
    # this sort need for prioritize routes by metrics
    return rv.sort_by{|r| r[:metric]||0}
  end

  def self.instances
    rv = []
    names = []
    routes = get_routes()
    routes.each do |route|
      _name = route[:network]
      if names.include? _name
        # calculate new name. lowers metrics always earlies.
        name = "#{_name},metric:#{route[:metric]}"
      else
        name = _name
        names << name
      end
      props = {
        :ensure         => :present,
        :name           => name,
      }
      props.merge! route
      props.delete(:metric) if props[:metric] == 0
      debug("PREFETCHED properties for '#{name}': #{props}")
      rv << new(props)
    end
    return rv
  end

  def exists?
    @property_hash[:ensure] == :present
  end

  def create
    debug("CREATE resource: #{@resource}")  # with hash: '#{m}'")
    @old_property_hash = {}
    @property_flush = {}.merge! @resource
    #p @property_flush
    #p @property_hash
    #p @resource.inspect
  end

  def destroy
    debug("DESTROY resource: #{@resource}")
    # todo: Destroing of L3 resource -- is a removing any IP addresses.
    #       DO NOT!!! put intedafce to Down state.
    iproute('--force', 'addr', 'flush', 'dev', @resource[:interface])
    @property_hash.clear
  end

  def initialize(value={})
    super(value)
    @property_flush = {}
    @old_property_hash = {}
    @old_property_hash.merge! @property_hash
  end

  def flush
    if @property_flush
      debug("FLUSH properties: #{@property_flush}")
      #
      # FLUSH changed properties
      if ! @property_flush[:ipaddr].nil?
        if @property_flush[:ipaddr].include?(:absent)
          # flush all ip addresses from interface
          iproute('--force', 'addr', 'flush', 'dev', @resource[:interface])
        elsif @property_flush[:ipaddr].include?(:dhcp)
          # start dhclient on interface
          iproute('--force', 'addr', 'flush', 'dev', @resource[:interface])
          #todo: start dhclient
        else
          # add-remove static IP addresses
          if !@old_property_hash.nil? and !@old_property_hash[:ipaddr].nil?
            (@old_property_hash[:ipaddr] - @property_flush[:ipaddr]).each do |ipaddr|
              iproute('--force', 'addr', 'del', ipaddr, 'dev', @resource[:interface])
            end
            adding_addresses = @property_flush[:ipaddr] - @old_property_hash[:ipaddr]
          else
            adding_addresses = @property_flush[:ipaddr]
          end
          if adding_addresses.include? :none
            iproute('--force', 'link', 'set', 'dev', @resource[:interface], 'up')
          elsif adding_addresses.include? :dhcp
            debug("!!! DHCP runtime configuration not implemented now !!!")
          else
            # add IP addresses
            adding_addresses.each do |ipaddr|
              iproute('addr', 'add', ipaddr, 'dev', @resource[:interface])
            end
          end
        end
      end

      if !@property_flush[:gateway].nil? or !@property_flush[:gateway_metric].nil?
        # clean all default gateways for this interface with any metrics
        cmdline = ['route', 'del', 'default', 'dev', @resource[:interface]]
        rc = 0
        while rc == 0
          # we should remove route repeatedly for prevent situation
          # when has multiple default routes through the same router,
          # but with different metrics
          begin
            iproute(cmdline)
          rescue
            rc = 1
          end
        end
        # add new route
        if @resource[:gateway] != :absent
          cmdline = ['route', 'add', 'default', 'via', @resource[:gateway], 'dev', @resource[:interface]]
          if ![nil, :absent].include?(@property_flush[:gateway_metric]) and @property_flush[:gateway_metric].to_i > 0
            cmdline << ['metric', @property_flush[:gateway_metric]]
          end
          begin
            rv = iproute(cmdline)
          rescue
            warn("!!! Iproute can't setup new gateway.\n!!! May be you already have default gateway with same metric:")
            rv = iproute('-f', 'inet', 'route', 'show')
            warn("#{rv}\n\n")
          end
        end
      end

      # if ! @property_flush[:onboot].nil?
      #   iproute('link', 'set', 'dev', @resource[:interface], 'up')
      # end
      @property_hash = resource.to_hash
    end
  end

  #-----------------------------------------------------------------
  # def bridge
  #   @property_hash[:bridge] || :absent
  # end
  # def bridge=(val)
  #   @property_flush[:bridge] = val
  # end

  # def name
  #   @property_hash[:name]
  # end

  def network
    @property_hash[:network] || :absent
  end
  def network=(val)
    @property_flush[:network] = val
  end

  def gateway
    @property_hash[:gateway] || :absent
  end
  def gateway=(val)
    @property_flush[:gateway] = val
  end

  def metric
    @property_hash[:metric] || :absent
  end
  def metric=(val)
    @property_flush[:metric] = val
  end

  def interface
    @property_hash[:interface] || :absent
  end
  def interface=(val)
    @property_flush[:interface] = val
  end

  def type
    @property_hash[:type] || :absent
  end
  def type=(val)
    @property_flush[:type] = val
  end

  #-----------------------------------------------------------------

  def self.get_if_addr_mappings
    if_list = {}
    ip_a = iproute('-f', 'inet', 'addr', 'show').split(/\n+/)
    if_name = nil
    ip_a.each do |line|
      line.rstrip!
      case line
      when /^\s*\d+\:\s+([\w\-\.]+)[\:\@]/i
        if_name = $1
        if_list[if_name] = { :ipaddr => [] }
      when /^\s+inet\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\/\d{1,2})/
        next if if_name.nil?
        if_list[if_name][:ipaddr] << $1
      else
        next
      end
    end
    return if_list
  end

  def self.get_if_defroutes_mappings
    rou_list = {}
    ip_a = iproute('-f', 'inet', 'route', 'show').split(/\n+/)
    ip_a.each do |line|
      line.rstrip!
      next if !line.match(/^\s*default\s+via\s+([\d\.]+)\s+dev\s+([\w\-\.]+)(\s+metric\s+(\d+))?/)
      metric = $4.nil?  ?  :absent  :  $4.to_i
      rou_list[$2] = { :gateway => $1, :gateway_metric => metric } if rou_list[$2].nil?  # do not replace to gateway with highest metric
    end
    return rou_list
  end


end
# vim: set ts=2 sw=2 et :