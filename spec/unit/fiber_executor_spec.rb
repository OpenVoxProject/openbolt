# frozen_string_literal: true

require 'spec_helper'
require 'bolt/fiber_executor'

describe "Bolt::FiberExecutor" do
  let(:fiber_executor)  { Bolt::FiberExecutor.new }
  let(:plan_id)         { 1234 }
  let(:mock_scope)      { double('scope', compiler: nil, to_hash: {}) }
  let(:mock_newscope)   { double('newscope', push_ephemerals: nil) }

  describe "#create_future" do
    it "creates a new scope if passed an existing scope" do
      expect(Puppet::Parser::Scope)
        .to receive(:new).and_return(mock_newscope)
      expect(Puppet::Parser::Scope::LocalScope)
        .to receive(:new).and_return({})

      fiber_executor.create_future(scope: mock_scope, plan_id: plan_id) { |_| return 0 }
    end

    it "does not create a new scope if an existing scope is not passed" do
      expect(Puppet::Parser::Scope)
        .not_to receive(:new)

      fiber_executor.create_future(plan_id: plan_id) { |_| return 0 }
    end

    it "creates a new PlanFuture object with a name" do
      expect(Bolt::PlanFuture).to receive(:new)
        .with(instance_of(Fiber), instance_of(Integer), name: 'name', plan_id: plan_id, scope: anything)
        .and_call_original
      fiber_executor.create_future(name: 'name', plan_id: plan_id) { |_| return 0 }
    end

    it "adds the PlanFuture to the list of futures" do
      fiber_executor.create_future(plan_id: plan_id) { |_| return 0 }
      expect(fiber_executor.active_futures.length).to eq(1)
      expect(fiber_executor.active_futures[0].class).to eq(Bolt::PlanFuture)
    end
  end

  describe "#round_robin" do
    before :each do
      @futures = %w[lion tiger bear].map do |val|
        fiber_executor.create_future(plan_id: plan_id) do
          sleep(rand(0.01..0.1))
          val + 's'
        end
      end
    end

    it "checks each fiber is alive twice per round_robin" do
      @futures.each do |future|
        expect(future).to receive(:alive?)
          .exactly(4).times
          .and_return(true, true, false, false)
      end

      fiber_executor.round_robin until fiber_executor.plan_complete?
    end

    it "resumes the fiber if it's still alive" do
      @futures.each do |future|
        # Return true once, then return false as many times as it's called
        allow(future).to receive(:alive?).and_return(true, false)
        expect(future).to receive(:resume)
      end

      fiber_executor.round_robin until fiber_executor.plan_complete?
    end

    it "removes PlanFutures from the FiberExecutor once it's done" do
      @futures.each do |future|
        # Return true once, then return false as many times as it's called
        allow(future).to receive(:alive?).and_return(true, false)
        expect(fiber_executor.active_futures).to receive(:delete)
          .with(future).and_call_original
      end

      fiber_executor.round_robin until fiber_executor.plan_complete?
      expect(fiber_executor.active_futures).to eq([])
    end

    it "sleeps if all futures returned immediately" do
      @futures.each do |future|
        # Return true once, then return false as many times as it's called
        allow(future).to receive(:alive?).and_return(true, true, false)
        allow(future).to receive(:resume) { future.value = :returned_immediately }
      end

      expect(fiber_executor).to receive(:sleep).at_least(:once)
      fiber_executor.round_robin until fiber_executor.plan_complete?
    end

    it "does not sleep after the last future finishes" do
      @futures.each do |future|
        allow(future).to receive(:alive?).and_return(true, false)
      end

      expect(fiber_executor).not_to receive(:sleep)
      fiber_executor.round_robin until fiber_executor.plan_complete?
    end
  end

  describe "#wait" do
    context "when passed 'nil' futures" do
      before :each do
        h = { 'lion' => 2, 'tiger' => 2, 'bear' => 3 }
        @futures = h.map do |val, p_id|
          dbl = double("future_#{val}", value: val + 's', original_plan: p_id, fiber: nil, nested_fibers: [])
          allow(dbl).to receive(:alive?).and_return(true, false)
          dbl
        end
        allow(fiber_executor).to receive(:all_futures).and_return(@futures)
        allow(fiber_executor).to receive(:wait).and_call_original
      end

      it "waits for all futures from the current plan invocation" do
        # Mock the plan ID
        expect(fiber_executor).to receive(:get_current_plan_id).and_return(2)

        # The actual thing we're testing - mock return to avoid yielding from
        # the root Fiber.
        expect(fiber_executor).to receive(:wait)
          .with(@futures[0..1], timeout: nil, catch_errors: false)

        fiber_executor.wait(nil)
      end

      it "returns results from all futures" do
        expect(fiber_executor).to receive(:get_current_plan_id).and_return(2)
        expect(fiber_executor.wait(nil)).to eq(%w[lions tigers])
      end

      it "continues getting futures until all futures have finished" do
        # Mock the plan ID
        expect(fiber_executor).to receive(:get_current_plan_id).and_return(2)

        # Assert that this loops
        expect(fiber_executor).to receive(:get_futures_for_plan)
          .with(plan_id: 2).twice
          .and_call_original

        fiber_executor.wait(nil)
      end
    end

    context "when passed a timeout" do
      before :each do
        @futures = %w[lion tiger bear].map do |val|
          name = "future_#{val}"
          error = Bolt::FutureTimeoutError.new(name, timeout)
          double(name, alive?: true, value: error, name: name)
        end
        allow(Fiber).to receive(:yield)
      end

      let(:timeout) { 0.1 }

      it "raises an error if any Futures exceed the timeout without catch_errors" do
        @futures.each do |f|
          # This is a little backwards since calling 'raise' should set the
          # value, not vice-versa, but it doesn't particularly matter for unit
          # testing.
          expect(f).to receive(:raise).with(f.value)
        end

        expect { fiber_executor.wait(@futures, timeout: timeout) }
          .to raise_error(Bolt::ParallelFailure, /parallel block failed on 3 targets/)
      end
    end

    context "when futures error" do
      before :each do
        @futures = %w[lion tiger bear].map do |val|
          name = "future_#{val}"
          error = Bolt::Error.new("Error", 'bolt/test-error')
          # Don't bother loading Puppet datatypes
          allow(error).to receive(:to_puppet_error).and_return(error)
          double(name, alive?: false, value: error, name: name)
        end
      end

      it "returns the result set if catch_errors is true" do
        expect { fiber_executor.wait(@futures, catch_errors: true) }.not_to raise_error
        expect(fiber_executor.wait(@futures, catch_errors: true))
          .to eq(@futures.map(&:value))
      end
    end
  end

  describe "#run_in_new_fiber" do
    before :each do
      # round_robin sleeps when no future can make progress
      allow(fiber_executor).to receive(:sleep)
    end

    def run_until_complete
      fiber_executor.round_robin until fiber_executor.plan_complete?
    end

    it "runs the block on the current Fiber when no future is running" do
      current = Fiber.current
      expect(fiber_executor.run_in_new_fiber { Fiber.current }).to eq(current)
    end

    it "runs each nested block on a new Fiber that belongs to the future" do
      seen = {}
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber do
          fiber_executor.run_in_new_fiber do
            seen[:fiber] = Fiber.current
            seen[:future] = fiber_executor.get_current_future(fiber: Fiber.current)
            seen[:nested] = seen[:future].nested_fibers.length
            'result'
          end
        end
      end
      run_until_complete

      expect(future.value).to eq('result')
      expect(seen[:fiber]).not_to eq(future.fiber)
      expect(seen[:future]).to eq(future)
      expect(seen[:nested]).to eq(2)
      expect(future.nested_fibers).to be_empty
    end

    it "passes what the block yields to the scheduler and returns the block's value" do
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber do
          Fiber.yield(:unfinished)
          'done'
        end
      end

      fiber_executor.round_robin
      expect(future.value).to eq(:unfinished)
      expect(future).to be_alive

      run_until_complete
      expect(future.value).to eq('done')
    end

    it "raises an error raised into the future, like a wait() timeout, inside the block" do
      received = nil
      timeout_error = Bolt::FutureTimeoutError.new('slow', 0.1)
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber do
          Fiber.yield(:unfinished)
        rescue Bolt::FutureTimeoutError => e
          received = e
          raise
        end
      rescue Bolt::FutureTimeoutError
        nil
      end

      fiber_executor.round_robin
      future.raise(timeout_error)

      expect(received).to equal(timeout_error)
      expect(future).not_to be_alive
      expect(future.nested_fibers).to be_empty
    end

    it "returns the block's value when the block rescues an error raised into the future" do
      returned = nil
      future = fiber_executor.create_future(plan_id: plan_id) do
        returned = fiber_executor.run_in_new_fiber do
          Fiber.yield(:unfinished)
        rescue Bolt::FutureTimeoutError
          'recovered'
        end
      end

      fiber_executor.round_robin
      future.raise(Bolt::FutureTimeoutError.new('slow', 0.1))

      expect(returned).to eq('recovered')
      expect(future).not_to be_alive
      expect(future.nested_fibers).to be_empty
    end

    it "raises an error from the block in the calling Fiber" do
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber { raise Bolt::Error.new('nested plan failed', 'bolt/test-error') }
      rescue Bolt::Error => e
        e
      end
      run_until_complete

      expect(future.value.message).to eq('nested plan failed')
      expect(future.nested_fibers).to be_empty
    end

    it "runs plans nested up to the limit" do
      stub_const('Bolt::FiberExecutor::MAX_NESTED_PLANS', 2)
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber do
          fiber_executor.run_in_new_fiber { 'at the limit' }
        end
      end
      run_until_complete

      expect(future.value).to eq('at the limit')
    end

    it "raises a clear error for plans nested past the limit" do
      stub_const('Bolt::FiberExecutor::MAX_NESTED_PLANS', 2)
      future = fiber_executor.create_future(plan_id: plan_id) do
        fiber_executor.run_in_new_fiber do
          fiber_executor.run_in_new_fiber do
            fiber_executor.run_in_new_fiber { 'past the limit' }
          end
        end
      rescue RuntimeError => e
        e
      end
      run_until_complete

      expect(future.value).not_to be_a(Bolt::Error)
      expect(future.value.message).to match(/nested more than 2 levels deep/)
      expect(future.nested_fibers).to be_empty
    end
  end
end
