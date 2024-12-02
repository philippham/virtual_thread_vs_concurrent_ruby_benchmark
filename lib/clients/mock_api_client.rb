class MockApiClient
  def initialize(name, latency: 0.1, error_rate: 0.01)
    @name = name
    @latency = latency
    @error_rate = error_rate
  end

  def fetch_data
    sleep(@latency)
    raise "#{@name} API Error" if rand < @error_rate

    {
      id: generate_id,
      timestamp: Time.now.strftime('%Y-%m-%dT%H:%M:%S.%L%z'),
      source: @name,
      data: generate_mock_data
    }
  end

  private

  def generate_id
    if defined?(java.util.UUID)
      java.util.UUID.randomUUID.toString
    else
      require 'securerandom'
      SecureRandom.uuid
    end
  end

  def generate_mock_data
    {
      items: 3.times.map { generate_item },
      metadata: {
        total: 3,
        page: 1,
        timestamp: Time.now.to_i
      }
    }
  end

  def generate_item
    {
      id: generate_id,
      name: "Item #{rand(1000)}",
      price: (rand * 100).round(2),
      category: ['Electronics', 'Fashion', 'Home'].sample
    }
  end
end