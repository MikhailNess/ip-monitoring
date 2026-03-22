# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:ip_checks) do
      primary_key :id

      foreign_key :ip_id, :ips, null: false, on_delete: :restrict, on_update: :cascade

      column :status, String, null: false
      column :rtt_ms, Float, null: true

      column :checked_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      check Sequel.lit("status IN ('success','timeout','error')")
      check Sequel.lit(
        "(status = 'success' AND rtt_ms IS NOT NULL AND rtt_ms >= 0)
         OR (status <> 'success' AND rtt_ms IS NULL)"
      )
    end

    add_index :ip_checks, %i[ip_id checked_at]
    add_index :ip_checks, :checked_at
    add_index :ip_checks, :status
  end
end
