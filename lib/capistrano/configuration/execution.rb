module Capistrano
  class Configuration
    module Execution
      def self.included(base)
        base.send :alias_method, :initialize_without_execution, :initialize
        base.send :alias_method, :initialize, :initialize_with_execution
      end

      # The call stack of the tasks. The currently executing task may inspect
      # this to see who its caller was. The current task is always the last
      # element of this stack.
      attr_reader :task_call_frames

      # The stack of tasks that have registered rollback handlers within the
      # current transaction. If this is nil, then there is no transaction
      # that is currently active.
      attr_reader :rollback_requests

      # A struct for representing a single instance of an invoked task.
      TaskCallFrame = Struct.new(:task, :rollback)

      def initialize_with_execution #:nodoc:
        initialize_without_execution
        @task_call_frames = []
      end
      private :initialize_with_execution

      # Returns true if there is a transaction currently active.
      def transaction?
        !rollback_requests.nil?
      end

      # Invoke a set of tasks in a transaction. If any task fails (raises an
      # exception), all tasks executed within the transaction are inspected to
      # see if they have an associated on_rollback hook, and if so, that hook
      # is called.
      def transaction
        raise ArgumentError, "expected a block" unless block_given?
        raise ScriptError, "transaction must be called from within a task" if task_call_frames.empty?

        return yield if transaction?

        logger.info "transaction: start"
        begin
          @rollback_requests = []
          yield
          logger.info "transaction: commit"
        rescue Object => e
          rollback!
          raise
        ensure
          @rollback_requests = nil
        end
      end

      # Specifies an on_rollback hook for the currently executing task. If this
      # or any subsequent task then fails, and a transaction is active, this
      # hook will be executed.
      def on_rollback(&block)
        task_call_frames.last.rollback = block
        rollback_requests << task_call_frames.last
      end

      # Returns the TaskDefinition object for the currently executing task.
      # It returns nil if there is no task being executed.
      def current_task
        return nil if task_call_frames.empty?
        task_call_frames.last.task
      end

      # Executes the task with the given name, including the before and after
      # hooks.
      def execute_task(name, namespace, fail_silently=false)
        name = name.to_sym
        unless task = namespace.tasks[name]
          return if fail_silently
          fqn = " in `#{namespace.fully_qualified_name}'" if namespace.parent
          raise NoMethodError, "no such task `#{name}'#{fqn}"
        end

        execute_task("before_#{name}", namespace, true)
        logger.debug "executing `#{task.fully_qualified_name}'"

        begin
          push_task_call_frame(task)
          result = instance_eval(&task.body)
        ensure
          pop_task_call_frame
        end

        execute_task("after_#{name}", namespace, true)
        result
      end

      protected

        def rollback!
          # throw the task back on the stack so that roles are properly
          # interpreted in the scope of the task in question.
          rollback_requests.reverse.each do |frame|
            begin
              push_task_call_frame(frame.task)
              logger.important "rolling back", frame.task.fully_qualified_name
              frame.rollback.call
            rescue Object => e
              logger.info "exception while rolling back: #{e.class}, #{e.message}", frame.task.fully_qualified_name
            ensure
              pop_task_call_frame
            end
          end
        end

        def push_task_call_frame(task)
          frame = TaskCallFrame.new(task)
          task_call_frames.push frame
        end

        def pop_task_call_frame
          task_call_frames.pop
        end
    end
  end
end