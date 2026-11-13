require_relative 'test_helper'
require 'tmpdir'
require 'json'
require 'koholint/leads'
require 'koholint/dialogues'
require 'koholint/trace'

class LeadsTest < Minitest::Test
  TEXT = "Hello, Link!\n\nThe  key is in the\nnorth cave. Shops sell bombs."

  def lead(quote, importance = 'high', claim: 'a claim') = { 'quote' => quote, 'claim' => claim, 'importance' => importance }

  def absorb(leads, raw) = leads.absorb(raw, transcription: TEXT, place: [1, 2], source: { row: 3, col: 4 })

  def test_a_quote_must_be_a_normalised_substring_of_the_transcription
    leads = Koholint::Leads.new
    accepted, rejected = absorb(leads, [lead('the key IS in the north   cave'), lead('the key is in the south cave'), lead('  ')])
    assert_equal 2, rejected
    assert_equal [[], 2], absorb(Koholint::Leads.new, [lead('Hello'), lead('x' * 301)])
    assert_equal [{ id: 'lead-1', place: [1, 2], source: { row: 3, col: 4 }, quote: 'the key IS in the north cave', claim: 'a claim', importance: 'high' }], accepted
  end

  def test_a_quote_may_match_the_stitched_text_or_the_raw_pages
    pages = ['the key is in', 'key is in the north cave']
    texts = [pages.join(' '), Koholint::Dialogues.text(pages)]
    accepted, rejected = Koholint::Leads.new.absorb([lead('key is in the north cave'), lead('the key is in the north')], transcription: texts, place: [1, 2], source: nil)
    assert_equal [2, 0], [accepted.size, rejected]
  end

  def test_bad_importance_missing_claims_and_garbage_are_rejected_and_long_claims_truncated
    leads = Koholint::Leads.new
    raw = [lead('Hello, Link', 'urgent'), { 'quote' => 'Hello, Link' }, 'Hello, Link', lead('Hello, Link', claim: "\n ")]
    assert_equal [[], 4], absorb(leads, raw)
    assert_equal [[], 0], absorb(leads, 'not a list')
    accepted, = absorb(leads, [lead('Hello, Link', claim: 'x' * 200)])
    assert_equal 160, accepted.first[:claim].size
  end

  def test_a_quote_matches_across_chunk_joins_whatever_the_whitespace
    pages = "Find the bo\n\nw near the well. Ask the old man."
    leads = Koholint::Leads.new
    accepted, rejected = leads.absorb([lead('the bow near the well'), lead('the oldman')], transcription: pages, place: [1, 2], source: nil)
    assert_equal [['the bow near the well', 'the oldman'], 0], [accepted.map { |l| l[:quote] }, rejected]
  end

  def test_duplicates_are_dropped_and_at_most_five_are_read_per_call
    leads = Koholint::Leads.new
    quotes = ['Hello, Link', 'hello,link', 'The key is', 'in the north', 'north cave', 'Shops sell', 'sell bombs']
    accepted, = absorb(leads, quotes.map { |q| lead(q) })
    assert_equal ['Hello, Link', 'The key is', 'in the north', 'north cave'], accepted.map { |l| l[:quote] }
    assert_equal [[], 0], absorb(leads, [lead('HELLO,  LINK')])
    assert_equal 'lead-5', absorb(leads, [lead('sell bombs', 'low')]).first.first[:id]
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
      trace.emit(:lead, frame: 1, id: 'lead-1', place: [1, 2], source: nil, quote: 'Hello, Link', claim: 'a greeting', importance: 'low')
      trace.emit(:goal, frame: 2, text: 'first')
      trace.emit(:goal, frame: 3, text: 'second')
      leads = Koholint::Leads.from_events(Koholint::Trace.read(File.join(dir, 'trace.jsonl')))
      assert_equal 'second', leads.goal
      assert leads.known?('lead-1')
      refute leads.known?('lead-2')
      assert_equal 'lead-2', absorb(leads, [lead('north cave')]).first.first[:id]
      assert_equal [[], 0], absorb(leads, [lead('hello, link')])
      Koholint::Leads.write_world(dir)
      world = JSON.parse(File.read(File.join(dir, 'world.json')))
      assert_equal 'second', world['goal']
      assert_equal [{ 'id' => 'lead-1', 'place' => [1, 2], 'source' => nil, 'quote' => 'Hello, Link', 'claim' => 'a greeting', 'importance' => 'low', 'status' => 'open', 'evidence' => [] }], world['leads']
    end
  end

  def test_objectives_that_followed_a_lead_test_or_refute_it_and_are_rebuilt_from_the_trace
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:lead, frame: 1, id: 'lead-1', place: [1, 2], source: nil, quote: 'the key is in the cave', claim: 'a key in the cave', importance: 'high', where: '5-0')
      trace.emit(:lead, frame: 1, id: 'lead-2', place: [1, 2], source: nil, quote: 'go further east', claim: 'east', importance: 'normal')
      trace.emit(:objective, frame: 10, id: 'obj-1', status: 'started', title: 'Go to place 5-0', predicate: { kind: 'reach_place', place: [5, 0] }, candidate: 'lead-1', target: { kind: 'lead', place: [5, 0], lead: 'lead-1' })
      trace.emit(:objective, frame: 90, id: 'obj-1', status: 'abandoned', predicate: { kind: 'reach_place', place: [5, 0] }, reason: 'stall')
      trace.emit(:objective, frame: 100, id: 'obj-2', status: 'started', title: 'Leave by the right side', predicate: { kind: 'leave_place', place: [1, 2] }, because: 'lead-2')
      trace.emit(:objective, frame: 150, id: 'obj-2', status: 'achieved', predicate: { kind: 'leave_place', place: [1, 2] })
      trace.emit(:objective, frame: 200, id: 'obj-3', status: 'started', title: 'Explore', predicate: { kind: 'new_place' })
      trace.emit(:objective, frame: 250, id: 'obj-3', status: 'failed', predicate: { kind: 'new_place' })
      leads = Koholint::Leads.from_events(Koholint::Trace.read(File.join(dir, 'trace.jsonl')))
      assert_equal ['open', 'tested'], leads.with_status.map { |lead| lead[:status] }
      assert_equal [{ objective: 'obj-2', lead: 'lead-2', title: 'Leave by the right side', outcome: 'achieved', place: [1, 2], frame: 150 }], leads.status(leads.all[1])[:evidence]
      assert_equal [{ objective: 'obj-1', lead: 'lead-1', title: 'Go to place 5-0', outcome: 'abandoned', place: [5, 0], frame: 90 }], leads.status(leads.all[0])[:evidence]
      leads.note_objective({ id: 'obj-4', title: 'Go to place 5-0', predicate: { kind: 'reach_place', place: [5, 0] }, outcome: :abandoned, ended_frame: 400, target: { kind: 'lead', place: [5, 0], lead: 'lead-1' } })
      leads.note_objective({ id: 'obj-4', title: 'again', outcome: :achieved, because: 'lead-1' })
      assert_equal ['refuted', 2], leads.status(leads.all[0]).then { |found| [found[:status], found[:evidence].size] }
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
      trace.emit(:objective, frame: 1, **started, predicate: { kind: 'new_text' })
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:objective, frame: 1, **started, predicate: { kind: 'find_item' }) }
    end
  end

  def test_a_where_hint_is_kept_and_resolves_to_a_place_id_or_a_place_name
    leads = Koholint::Leads.new
    accepted, = absorb(leads, [lead('north cave').merge('where' => " north\ncave "), lead('Shops sell', 'low').merge('where' => '161-0'), lead('Hello, Link').merge('where' => '')])
    assert_equal ['north cave', '161-0', nil], accepted.map { |l| l[:where] }
    assert_nil leads.place_for(accepted[0])
    assert_equal [161, 0], leads.place_for(accepted[1])
    assert_equal 'North Cave', leads.name_place([5, 0], ' North  Cave ')
    assert_nil leads.name_place([5, 0], 'North Cave')
    assert_nil leads.name_place('5-0', 'x')
    assert_equal [5, 0], leads.place_for(accepted[0])
    assert_equal({ [5, 0] => 'North Cave' }, leads.names)
  end

  def test_place_names_and_where_hints_are_rebuilt_from_the_trace_and_written_in_world_json
    Dir.mktmpdir do |dir|
      trace = Koholint::Trace.new(File.join(dir, 'trace.jsonl'))
      trace.emit(:lead, frame: 1, id: 'lead-1', place: [1, 2], source: nil, quote: 'Hello, Link', claim: 'a greeting', importance: 'low', where: 'beach')
      trace.emit(:place_card, frame: 2, place: [1, 2], people: [], enemies: [], unknown: [], signs: [], objects: [], doors: [], exits: {})
      trace.emit(:place_name, frame: 3, place: [1, 2], name: 'Beach')
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:place_name, frame: 3, place: [1, 2], name: '') }
      assert_raises(Koholint::Trace::InvalidEvent) { trace.emit(:lead, frame: 1, id: 'lead-2', place: [1, 2], source: nil, quote: 'q', claim: 'c', importance: 'low', where: 'x' * 41) }
      leads = Koholint::Leads.from_events(Koholint::Trace.read(File.join(dir, 'trace.jsonl')))
      assert_equal [1, 2], leads.place_for(leads.all.first)
      Koholint::Leads.write_world(dir)
      world = JSON.parse(File.read(File.join(dir, 'world.json')))
      assert_equal 'Beach', world['places']['1-2']['name']
      assert_equal 'beach', world['leads'].first['where']
    end
  end
end
