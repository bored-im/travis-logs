# frozen_string_literal: true

require 'metriks'

module Travis
  module Logs
    module MetricsMethods
      def measure(name = nil, &block)
      end

      def mark(name)
      end
    end
  end
end
