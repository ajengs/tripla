class BaseService
  attr_accessor :result

  def valid?
    errors.blank?
  end

  def errors
    @errors ||= []
  end
  
  def upstream_error?
    @upstream_error || false
  end

  protected

  def upstream_error!
    @upstream_error = true
  end
end
