require 'logger'
require 'heroku-log-parser'
require_relative './queue_io.rb'
require_relative ENV.fetch("WRITER_LIB", "./writer/s3.rb") # provider of `Writer < WriterBase` singleton

class App
  PREFIX = ENV.fetch("FILTER_PREFIX", "")
  PREFIX_LENGTH = PREFIX.length
  LOG_REQUEST_URI = ENV['LOG_REQUEST_URI']
  APPS = ENV.fetch("APPS", "").split(";")

  def initialize
    @logger = Logger.new(STDOUT)
    @logger.formatter = proc do |severity, datetime, progname, msg|
       "[app #{$$} #{Thread.current.object_id}] #{msg}\n"
    end
    @logger.info "initialized"

    APPS.each do |app_name|
      Object.const_set(classify(app_name), Class.new(Writer))
    end
  end

  def call(env)
    lines = if LOG_REQUEST_URI
      [env['REQUEST_URI']]
    else
      HerokuLogParser.parse(env['rack.input'].read).collect {|m| "#{m[:emitted_at]} #{m[:proc_id]} #{m[:msg_id]} #{m[:message]}" }
    end

    app_name = env['REQUEST_URI'][1..-1]
    lines.each do |line|
      next unless line.start_with?(PREFIX)
      Object.const_get(classify(app_name)).instance.write(app_name, line[PREFIX_LENGTH..-1]) # WRITER_LIB
    end

  rescue Exception
    @logger.error $!
    @logger.error $@

  ensure
    return [200, { 'Content-Length' => '0' }, []]
  end

  def classify(name)
    name.split(/_|-/).collect(&:capitalize).join
  end
end
