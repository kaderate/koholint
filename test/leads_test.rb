require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/leads'
require 'koholint/trace'

class LeadsTest < Minitest::Test
  TEXT = "Hello, Link!\n\nThe  key is in the\nnorth cave. Shops sell bombs."

  def lead(quote, importance = 'high', claim: 'a claim') = { 'quote' => quote, 'claim' => claim, 'importance' => importance }

  def absorb(leads, raw) = leads.absorb(raw, transcription: TEXT, place: [1, 2], source: { row: 3, col: 4 })

  def test_a_quote_must_be_a_normalised_substring_of_the_transcription
    leads = Koholint::Leads.new
    accepted, rejected = absorb(leads, [lead('the key IS in the north   cave'), lead('the key is in the south cave'), lead('  ')])
    assert_equal 2, rejected
    assert_equal [{ id: 'lead-1', place: [1, 2], source: { row: 3, col: 4 }, quote: 'the key IS in the north cave', claim: 'a claim', importance: 'high' }], accepted
  end

  def test_bad_importance_long_or_missing_claims_and_garbage_are_rejected
    leads = Koholint::Leads.new
    raw = [lead('Hello', 'urgent'), lead('Hello', claim: 'x' * 161), { 'quote' => 'Hello' }, 'Hello', lead('Hello', claim: "\n ")]
    assert_equal [[], 5], absorb(leads, raw)
    assert_equal [[], 0], absorb(leads, 'not a list')
  end

  def test_duplicates_are_dropped_and_at_most_five_are_read_per_call
    leads = Koholint::Leads.new
    accepted, = absorb(leads, [lead('Hello'), lead('hello,'), lead('Link'), lead('key'), lead('north'), lead('cave'), lead('bombs')])
    assert_equal %w[Hello hello, Link key north], accepted.map { |l| l[:quote] }
    assert_equal [[], 0], absorb(leads, [lead('HELLO')])
    assert_equal 'lead-6', absorb(leads, [lead('bombs', 'low')]).first.first[:id]
  end

  def test_the_goal_is_cleaned_capped_and_reported_only_when_it_changes
    leads = Koholint::Leads.new
    assert_equal 'find the key', leads.change_goal("  find\nthe key ")
    assert_nil leads.change_goal('find the key')
    assert_nil leads.change_goal('')
    assert_nil leads.change_goal(nil)
    assert_equal 120, leads.change_goal('x' * 300).size
  end

  def test_the_state_is_rebuilt_from_trace_events_and_written_as_world_json
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:lead, frame: 1, id: 'lead-1', place: [1, 2], source: nil, quote: 'Hello', claim: 'a greeting', importance: 'low')
      trace.emit(:goal, frame: 2, text: 'first')
      trace.emit(:goal, frame: 3, text: 'second')
      leads = Koholint::Leads.from_events(Koholint::Trace.read(File.join(dir, 'trace.jsonl')))
      assert_equal 'second', leads.goal
      assert leads.known?('lead-1')
      refute leads.known?('lead-2')
      assert_equal 'lead-2', absorb(leads, [lead('north cave')]).first.first[:id]
      assert_equal [[], 0], absorb(leads, [lead('hello')])
      Koholint::Leads.write_world(dir)
      world = JSON.parse(File.read(File.join(dir, 'world.json')))
      assert_equal 'second', world['goal']
      assert_equal [{ 'id' => 'lead-1', 'place' => [1, 2], 'source' => nil, 'quote' => 'Hello', 'claim' => 'a greeting', 'importance' => 'low' }], world['leads']
    end
  end

  def test_the_trace_validates_lead_goal_and_because
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      fields = { id: 'lead-1', place: [1, 2], source: nil, quote: 'q', claim: 'c', importance: 'high' }
      trace.emit(:lead, frame: 1, **fields)
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:lead, frame: 1, **fields, importance: 'urgent') }
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:lead, frame: 1, **fields.except(:quote)) }
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:goal, frame: 1) }
      started = { id: 'obj-1', status: 'started', predicate: { kind: 'new_place' } }
      trace.emit(:objective, frame: 1, **started, because: 'lead-1')
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:objective, frame: 1, **started, because: 'the old man') }
    end
  end
end
