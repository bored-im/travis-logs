# frozen_string_literal: true

require 'bunny'
require 'coder'
require 'concurrent'
require 'multi_json'
require 'thread'
require 'timeout'

require 'travis/logs'

module Travis
  module Logs
    class DrainQueue
      include Travis::Logs::MetricsMethods

      METRIKS_PREFIX = 'logs.queue'

      def self.metriks_prefix
        METRIKS_PREFIX
      end

      def self.subscribe(name, &handler_callable)
        new(name, &handler_callable).subscribe
      end

      attr_reader :name, :handler_callable, :periodic_flush_task

      def initialize(name, &handler_callable)
        @name = name
        @handler_callable = handler_callable
        @periodic_flush_task = build_periodic_flush_task
      end

      def subscribe
        jobs_queue.subscribe(manual_ack: true, &method(:receive))
      end

      private def jobs_queue
        @jobs_queue ||= jobs_channel.queue(
          "reporting.jobs.#{name}", durable: true, exclusive: false
        )
      end

      private def jobs_channel
        @jobs_channel ||= amqp_conn.create_channel
      end

      private def batch_size
        @batch_size ||= Integer(logs_config[:drain_batch_size] || 0)
      end

      private def amqp_conn
        @amqp_conn ||= Bunny.new(amqp_config).tap(&:start)
      end

      private def amqp_config
        @amqp_config ||= Travis.config.amqp.to_h
      end

      private def logs_config
        @logs_config ||= Travis.config.logs.to_h
      end

      private def batch_buffer
        @batch_buffer ||= Concurrent::Map.new
      end

      private def flush_mutex
        @flush_mutex ||= Mutex.new
      end

      private def build_periodic_flush_task
        Concurrent::TimerTask.new(
          execution_interval: logs_config[:drain_execution_interval],
          timeout_interval: logs_config[:drain_timeout_interval]
        ) do
          flush_mutex.synchronize { flush_batch_buffer }
        end
      end

      private def flush_batch_buffer
        Travis.logger.info('flushing batch buffer', size: batch_buffer.size)
        sample = {}
        payload = []

        batch_buffer.each_pair do |delivery_tag, entry|
          sample[delivery_tag] = entry
        end

        sample.each_pair do |delivery_tag, entry|
          payload.push(entry)

          begin
            batch_buffer.delete_pair(delivery_tag, entry)
          rescue StandardError => e
            Travis.logger.error(
              'failed to delete pair from buffer',
              error: e.inspect
            )
            payload.pop
            next
          end

          begin
            jobs_channel.ack(delivery_tag, true)
          rescue StandardError => e
            Travis.logger.error(
              'failed to ack message',
              error: e.inspect
            )
            payload.pop
            batch_buffer[delivery_tag] = entry
          end
        end

        handler_callable.call(payload)
      end

      private def receive(delivery_info, _properties, payload)
        decoded_payload = nil
        smart_retry do
          decoded_payload = decode(payload)
          if decoded_payload
            batch_buffer[delivery_info.delivery_tag] = decoded_payload
            if batch_buffer.size >= batch_size
              flush_mutex.synchronize { flush_batch_buffer }
            end
          else
            Travis.logger.info('acking empty or undecodable payload')
            jobs_channel.ack(delivery_info.delivery_tag, true)
          end
        end
      rescue => e
        log_exception(e, decoded_payload)
        jobs_channel.reject(delivery_info.delivery_tag, true)
        mark('receive.retry')
        Travis.logger.error('message requeued', stage: 'queue:receive')
      end

      private def smart_retry(retries: 2, timeout: 3, &block)
        retry_count = 0
        begin
          Timeout.timeout(timeout, &block)
        rescue Timeout::Error, Sequel::PoolTimeout
          if retry_count < retries
            retry_count += 1
            Travis.logger.error(
              'processing AMQP message timeout exceeded',
              action: 'receive',
              timeout_seconds: timeout,
              retry: retry_count,
              max_retries: retries
            )
            mark('timeout.retry')
            retry
          else
            Travis.logger.error(
              'failed to process AMQP message, aborting',
              action: 'receive',
              max_retries: retries
            )
            mark('timeout.error')
            raise
          end
        end
      end

      private def decode(payload)
        return payload if payload.is_a?(Hash)
        payload = Coder.clean(payload)
        MultiJson.load(payload)
      rescue StandardError => e
        Travis.logger.error(
          'payload could not be decoded',
          error: e.inspect,
          payload: payload.inspect,
          stage: 'queue:decode'
        )
        mark('payload.decode_error')
        nil
      end

      private def log_exception(error, payload)
        Travis.logger.error(
          'exception caught in queue while processing payload',
          action: 'receive',
          queue: name,
          payload: payload.inspect
        )
        Travis::Exceptions.handle(error)
      rescue StandardError => e
        Travis.logger.error("!!!FAILSAFE!!! #{e.message}")
        Travis.logger.error(e.backtrace.first)
      end
    end
  end
end
