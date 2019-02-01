module RLS
  def self.disable!
    ActiveRecord::Base.connection.execute("SET SESSION rls.disable = TRUE;")
    print "WARNING: ROW LEVEL SECURITY DISABLED!\n"
  end

  def self.enable!
    ActiveRecord::Base.connection.execute("SET SESSION rls.disable = FALSE;")
    print "ROW LEVEL SECURITY ENABLED!\n"
  end

  def self.set_tenant tenant
    raise "Tenant is nil!" unless tenant.present?
    print "Accessing database as #{tenant.name}\n"
    ActiveRecord::Base.connection.execute "SET SESSION rls.disable = FALSE; SET SESSION rls.tenant_id = #{tenant.id&.to_s};"
  end

  def self.disable_for_block &block
    if self.disabled?
      yield(block)
    else
      self.disable!
      begin
        yield(block)
      ensure
        self.enable!
      end
    end
  end

  def self.set_tenant_for_block tenant, &block
    tenant_was = self.current_tenant_id
    self.set_tenant tenant
    yield tenant, block
  ensure
    if tenant_was
      ActiveRecord::Base.connection.execute "SET SESSION rls.tenant_id = #{tenant_was};"
    else
      ActiveRecord::Base.connection.execute "RESET rls.tenant_id;"
    end
  end

  def self.run_per_tenant &block
    tenant_class.all.each do |tenant|
      RLS.set_tenant tenant
      yield tenant, block
    end
  end

  def self.current_tenant_id
    ActiveRecord::Base.connection.execute("SELECT current_setting('rls.tenant_id', TRUE);").values[0][0].presence
  end

  def self.enabled?
    !self.disabled?
  end

  def self.disabled?
    ActiveRecord::Base.connection.execute("SELECT NULLIF(current_setting('rls.disable', TRUE), '')::BOOLEAN;").values[0][0] === true
  end

  def self.reset!
    print "Resetting RLS settings.\n"
    ActiveRecord::Base.connection.execute "RESET rls.tenant_id;"
    ActiveRecord::Base.connection.execute "RESET rls.disable;"
  end

  def self.status
    query = "SELECT current_setting('rls.tenant_id', TRUE), current_setting('rls.disable', TRUE);"
    result = ActiveRecord::Base.connection.execute(query).values[0]
    [:tenant_id, :disable_rls].zip(result).to_h
  end

  def self.current_tenant
    id = current_tenant_id
    return nil unless id
    tenant_class.find id
  end

  def self.tenant_class
    Railtie.config.rls_rails.tenant_class
  end
end