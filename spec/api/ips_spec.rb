# frozen_string_literal: true

require_relative '../spec_helper'

RSpec.describe 'IPs API', type: :request do
  def post_create_ip(ip:, enabled:)
    post '/ips', { ip: ip, enabled: enabled }
  end

  def parsed_body
    JSON.parse(last_response.body)
  end

  describe 'POST /ips' do
    it 'creates an IP and returns 201' do
      post_create_ip(ip: '10.0.0.1', enabled: 'false')

      expect(last_response.status).to eq(201)
      expect(parsed_body['ip']).to eq('10.0.0.1')
      expect(parsed_body['enabled']).to be(false)
      expect(parsed_body['id']).to be_a(Integer)
    end

    it 'returns 409 when the active IP already exists' do
      post_create_ip(ip: '10.0.0.2', enabled: 'false')
      expect(last_response.status).to eq(201)

      post_create_ip(ip: '10.0.0.2', enabled: 'false')
      expect(last_response.status).to eq(409)
      expect(parsed_body.dig('error', 'code')).to eq('CONFLICT')
    end

    it 'after DELETE recreates the same row by IP with the same id' do
      post_create_ip(ip: '10.0.0.8', enabled: 'false')
      id = parsed_body['id']

      delete "/ips/#{id}"
      expect(last_response.status).to eq(204)

      post_create_ip(ip: '10.0.0.8', enabled: 'true')
      expect(last_response.status).to eq(201)
      expect(parsed_body['id']).to eq(id)
      expect(parsed_body['ip']).to eq('10.0.0.8')
      expect(parsed_body['enabled']).to be(true)
    end
  end

  describe 'POST /ips/:id/enable' do
    it 'opens monitoring for stats collection' do
      post_create_ip(ip: '10.0.0.3', enabled: 'false')
      id = parsed_body['id']

      post "/ips/#{id}/enable"

      expect(last_response.status).to eq(200)
      expect(parsed_body['id']).to eq(id)
      expect(parsed_body['enabled']).to be(true)
      expect(parsed_body).to have_key('changed')
    end
  end

  describe 'GET /ips/:id/stats' do
    it 'returns 422 when there are no checks in the requested window' do
      post_create_ip(ip: '10.0.0.4', enabled: 'true')
      id = parsed_body['id']

      # Future window: activity period exists but no checks fall inside it
      from_future = Time.now.utc + 3600
      to_future = from_future + 3600

      get "/ips/#{id}/stats", {
        time_from: from_future.iso8601,
        time_to: to_future.iso8601
      }

      expect(last_response.status).to eq(422)
      expect(parsed_body.dig('error', 'code')).to eq('UNPROCESSABLE_ENTITY')
    end

    it 'returns aggregates when successful checks exist' do
      post_create_ip(ip: '10.0.0.5', enabled: 'true')
      id = parsed_body['id']

      now = Time.now.utc
      period_start = now - 7200
      checked_at = now - 1800

      DB[:ip_activity_periods].where(ip_id: id).update(started_at: period_start)
      DB[:ip_checks].insert(
        ip_id: id,
        status: 'success',
        rtt_ms: 10,
        checked_at: checked_at,
        created_at: checked_at
      )

      get "/ips/#{id}/stats", {
        time_from: (period_start - 60).iso8601,
        time_to: (now + 60).iso8601
      }

      expect(last_response.status).to eq(200)
      expect(parsed_body['avg_rtt_ms']).to eq(10.0)
      expect(parsed_body['min_rtt_ms']).to eq(10.0)
      expect(parsed_body['max_rtt_ms']).to eq(10.0)
      expect(parsed_body['median_rtt_ms']).to eq(10.0)
      expect(parsed_body['loss_percent']).to eq(0.0)
    end

    it 'aggregates checks across merged enable intervals (gap where monitoring was off)' do
      post_create_ip(ip: '10.0.0.51', enabled: 'false')
      id = parsed_body['id']

      base = Time.utc(2030, 6, 15, 14, 0, 0)
      p1_end = base + 60
      p2_start = base + 120
      p2_end = base + 180
      now_ins = base

      DB[:ip_activity_periods].insert(
        ip_id: id,
        started_at: base,
        ended_at: p1_end,
        created_at: now_ins,
        updated_at: now_ins
      )
      DB[:ip_activity_periods].insert(
        ip_id: id,
        started_at: p2_start,
        ended_at: p2_end,
        created_at: now_ins,
        updated_at: now_ins
      )

      DB[:ip_checks].insert(ip_id: id, status: 'success', rtt_ms: 10, checked_at: base + 30, created_at: base + 30)
      DB[:ip_checks].insert(ip_id: id, status: 'success', rtt_ms: 999, checked_at: base + 90, created_at: base + 90)
      DB[:ip_checks].insert(ip_id: id, status: 'success', rtt_ms: 30, checked_at: p2_start + 30,
                            created_at: p2_start + 30)

      get "/ips/#{id}/stats", {
        time_from: (base - 60).iso8601,
        time_to: (p2_end + 60).iso8601
      }

      expect(last_response.status).to eq(200)
      expect(parsed_body['avg_rtt_ms']).to eq(20.0)
      expect(parsed_body['min_rtt_ms']).to eq(10.0)
      expect(parsed_body['max_rtt_ms']).to eq(30.0)
      expect(parsed_body['loss_percent']).to eq(0.0)
    end

    it 'returns 422 when merged activity intervals contain no checks' do
      post_create_ip(ip: '10.0.0.52', enabled: 'false')
      id = parsed_body['id']

      base = Time.utc(2030, 6, 15, 16, 0, 0)
      now_ins = base

      DB[:ip_activity_periods].insert(
        ip_id: id,
        started_at: base,
        ended_at: base + 60,
        created_at: now_ins,
        updated_at: now_ins
      )
      DB[:ip_activity_periods].insert(
        ip_id: id,
        started_at: base + 120,
        ended_at: base + 180,
        created_at: now_ins,
        updated_at: now_ins
      )

      DB[:ip_checks].insert(ip_id: id, status: 'success', rtt_ms: 1, checked_at: base + 90, created_at: base + 90)

      get "/ips/#{id}/stats", {
        time_from: (base - 60).iso8601,
        time_to: (base + 240).iso8601
      }

      expect(last_response.status).to eq(422)
      expect(parsed_body.dig('error', 'code')).to eq('UNPROCESSABLE_ENTITY')
    end
  end

  describe 'DELETE /ips/:id' do
    it 'deletes the IP and a second DELETE returns 404' do
      post_create_ip(ip: '10.0.0.6', enabled: 'false')
      id = parsed_body['id']

      delete "/ips/#{id}"

      expect(last_response.status).to eq(204)

      delete "/ips/#{id}"
      expect(last_response.status).to eq(404)
    end
  end
end
