# frozen_string_literal: true

require 'spec_helper'
require 'bolt_spec/pal'
require 'bolt/pal'

describe 'ApplyResult DataType' do
  include BoltSpec::PAL

  before(:all) { Bolt::PAL.load_puppet }
  after(:each) { Puppet.settings.send(:clear_everything_for_tests) }

  let(:pal) { make_pal }
  let(:inventory) { make_inventory }

  let(:result_code) do
    <<~PUPPET
      $result = results::make_apply_result('ssh://example.com', {'report' => {}})
    PUPPET
  end

  def result_attr(attr)
    code = result_code + attr
    peval(code, pal, nil, inventory)
  end

  it 'should expose target' do
    expect(result_attr('$result.target.uri')).to eq('ssh://example.com')
  end

  it 'should expose the report' do
    expect(result_attr('$result.report')).to eq({})
  end

  it 'should be ok' do
    expect(result_attr('$result.ok')).to eq(true)
  end

  context 'with an error result' do
    let(:result_code) do
      <<~PUPPET
        $result = results::make_result('ssh://example.com',
                    { '_error' => {
                        'msg' => 'oops',
                        'kind' => 'bolt/oops',
                        'details' => {'detailk' => 'detailv'}
                        }
                    })
      PUPPET
    end

    it 'should not be ok' do
      expect(result_attr('$result.ok')).to eq(false)
    end

    it 'should expose the error kind' do
      expect(result_attr('$result.error.kind')).to eq('bolt/oops')
    end

    it 'should expose the error message' do
      expect(result_attr('$result.error.message')).to eq('oops')
    end

    it 'should expose the error kind' do
      expect(result_attr("$result.error.details['detailk']")).to eq('detailv')
    end
  end
end
