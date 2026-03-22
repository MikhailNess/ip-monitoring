# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:ip_activity_periods) do
      primary_key :id

      foreign_key :ip_id, :ips, null: false, on_delete: :restrict, on_update: :cascade

      column :started_at, :timestamptz, null: false
      column :ended_at, :timestamptz, null: true

      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP

      check Sequel.lit('started_at <= ended_at OR ended_at IS NULL')
    end

    add_index :ip_activity_periods, %i[ip_id started_at]
    add_index :ip_activity_periods, %i[ip_id ended_at]
    add_index :ip_activity_periods, :started_at

    run <<~SQL
      CREATE UNIQUE INDEX index_ip_activity_periods_on_ip_id_open
      ON ip_activity_periods (ip_id)
      WHERE ended_at IS NULL;
    SQL
  end
end
