require 'redis'

redis = Redis.new(host: "127.0.0.1", port: 6379)
redis.pipelined do |r|
  r.del("queue:default")
  50_000.times do |i|
    value = "{\"jid\": \"aaaa\",\"class\":\"EchoWorker\",\"args\":{\"message\":\"#{i}\"},\"retry\":1,\"queue\":\"default\"}"
    r.lpush("queue:default", value)
  end

  50_000.times do |i|
    value = "{\"jid\": \"aaaa\",\"class\":\"EchoWorker\",\"args\":{\"message\":\"#{i}\"},\"retry\":1,\"queue\":\"other\"}"
    r.lpush("queue:other", value)
  end
end
