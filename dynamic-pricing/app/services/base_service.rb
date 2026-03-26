class BaseService
  attr_accessor :result
  attr_reader :error_code

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
    @error_code = :upstream_error
  end
end
