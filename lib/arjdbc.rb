if defined?(JRUBY_VERSION)
  begin
    require 'active_record/version'
    require 'active_record'
  rescue LoadError => e
    warn "activerecord-jdbc-adapter requires the activerecord gem at runtime"
    raise e
  end
  require 'arjdbc/jdbc'
  begin
    require 'arjdbc/railtie'
  rescue LoadError => e
    warn "activerecord-jdbc-adapter failed to load railtie: #{e.inspect}"
  end if defined?(Rails) && ActiveRecord::VERSION::MAJOR >= 3
else
  warn "activerecord-jdbc-adapter is for use with JRuby only"
end

require 'arjdbc/version'

warn "NOTE: AR-JDBC 1.4 takes time to iron out, if you do like where its" +
" heading please consider supporting the project http://bit.ly/arjdbc14 "