# type for managing routes in runtime.

Puppet::Type.newtype(:l3_route) do
    @doc = "Manage a network routings."
    desc @doc

    ensurable

    newparam(:name) # workarround for following error:
    # Error 400 on SERVER: Could not render to pson: undefined method `merge' for []:Array
    # http://projects.puppetlabs.com/issues/5220


    newproperty(:network) do
      desc "Destination network"
      validate do |val|
        val.strip!
        raise ArgumentError, "Invalid IP address in list: '#{val}'" if \
           not val.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(\/(\d{1,2}))?$/) \
           or not ($1.to_i >= 0  and  $1.to_i <= 255) \
           or not ($2.to_i >= 0  and  $2.to_i <= 255) \
           or not ($3.to_i >= 0  and  $3.to_i <= 255) \
           or not ($4.to_i >= 0  and  $4.to_i <= 255) \
           or not ($6.to_i >= 0  and  $6.to_i <= 32)
      end
      # def should_to_s(value)
      #   value.inspect
      # end
      # def is_to_s(value)
      #   value.inspect
      # end
    end

    newproperty(:gateway) do
      desc "Gateway"
      newvalues(/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/, :absent, :none, :undef, :nil)
      aliasvalue(:none,  :absent)
      aliasvalue(:undef, :absent)
      aliasvalue(:nil,   :absent)
      defaultto :absent
      validate do |val|
        if val != :absent
          val.strip!
          raise ArgumentError, "Invalid gateway: '#{val}'" if \
             not val.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/) \
             or not ($1.to_i >= 0  and  $1.to_i <= 255) \
             or not ($2.to_i >= 0  and  $2.to_i <= 255) \
             or not ($3.to_i >= 0  and  $3.to_i <= 255) \
             or not ($4.to_i >= 0  and  $4.to_i <= 255)
        end
      end
    end

    newproperty(:metric) do
      desc "Route metric"
      newvalues(/^\d+$/, :absent, :none, :undef, :nil)
      aliasvalue(:none,  :absent)
      aliasvalue(:undef, :absent)
      aliasvalue(:nil,   :absent)
      aliasvalue(0,      :absent)
      validate do |val|
        min_metric = 0
        max_metric = 65535
        if ! (val.to_s == 'absent' or (min_metric .. max_metric).include?(val.to_i))
          raise ArgumentError, "'#{val}' is not a valid metric (must be a integer value in range (#{min_metric} .. #{max_metric})"
        end
      end
      munge do |val|
        ((val == :absent)  ?  :absent  :  val.to_i)
      end
    end

    newproperty(:interface) do
      newvalues(/^[a-z_][0-9a-z\.\-\_]*[0-9a-z]$/)
      desc "The interface name"
    end

    newproperty(:type) do
      desc "RO field, type of route"
    end

    autorequire(:l2_port) do
      [self[:interface]]
    end
end
# vim: set ts=2 sw=2 et :