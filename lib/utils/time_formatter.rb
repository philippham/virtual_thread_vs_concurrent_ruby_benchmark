module TimeFormatter
  def self.format_time(time)
    time.strftime('%Y-%m-%dT%H:%M:%S.%L%z')
  end

  def self.current_timestamp
    format_time(Time.now)
  end
end