module DCell
  # A node in a DCell cluster
  class Node
    include Celluloid
    attr_reader :id, :addr

    @nodes = {}
    @lock  = Mutex.new

    class << self
      # Find a node by its node ID
      def find(id)
        node = @lock.synchronize { @nodes[id] }
        return node if node

        addr = Directory.get(id)

        if addr
          if id == DCell.id
            node = DCell.me
          else
            node = Node.new(id, addr)
          end

          @lock.synchronize { @nodes[id] = node }

          node
        end
      end
      alias_method :[], :find
    end

    def initialize(id, addr)
      @id, @addr = id, addr
      @socket = DCell.zmq_context.socket(::ZMQ::PUSH)

      unless ::ZMQ::Util.resultcode_ok? @socket.connect(@addr)
        @socket.close
      end
    end

    # Find an actor registered with a given name on this node
    def find(name)
      our_mailbox = Thread.current.mailbox
      request = LookupRequest.new(our_mailbox, name)
      send_message request

      if Celluloid.actor?
        # Yield to the actor scheduler, which resumes us when we get a response
        response = Fiber.yield(request)
      else
        # Otherwise we're inside a normal thread, so block
        response = our_mailbox.receive do |msg|
          msg.is_a? Response and msg.call == call
        end
      end
    end
    alias_method :[], :find

    # Send a message to another DCell node
    def send_message(message)
      @socket.send_string Marshal.dump(message)
    end
  end
end
