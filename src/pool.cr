require "mutex"
require "./artist"

module Earl
  class Pool(A, M)
    include Artist(M)

    def initialize(@capacity : Int32)
      @workers = Array(A).new(@capacity)
      @mutex = Mutex.new
      @fiber = nil
    end

    def call : Nil
      @capacity.times do
        spawn do
          agent = A.new
          @mutex.synchronize { @workers << agent }

          while agent.starting?
            Earl.logger.info "#{self.class.name} starting worker[#{agent.object_id}]"
            agent.mailbox = mailbox
            agent.start(link: self)
          end
        end
      end

      @fiber = Fiber.current
      Scheduler.reschedule

      until @workers.empty?
        Fiber.yield
      end
    end

    def trap(agent : A, exception : Exception?) : Nil
      if exception
        Earl.logger.error "#{self.class.name} worker[#{agent.object_id}] crashed message=#{exception.message} (#{exception.class.name})"
        return agent.recycle if running?
      end

      if agent.running?
        Earl.logger.warn "#{self.class.name} worker[#{agent.object_id}] stopped unexpectedly"
        return agent.recycle
      else
        @mutex.synchronize { @workers.delete(agent) }
      end
    end

    def terminate : Nil
      @workers.each do |agent|
        begin
          agent.stop
        rescue ex
        end
      end

      if fiber = @fiber
        @fiber = nil
        Scheduler.enqueue(fiber)
      end
    end
  end
end
