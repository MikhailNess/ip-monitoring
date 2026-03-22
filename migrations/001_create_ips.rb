# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:ips) do
      primary_key :id

      column :ip, :inet, null: false

      column :created_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :updated_at, :timestamptz, null: false, default: Sequel::CURRENT_TIMESTAMP
      column :deleted_at, :timestamptz, null: true
    end

    run <<~SQL
      CREATE UNIQUE INDEX index_ips_on_ip_active
      ON ips (ip)
      WHERE deleted_at IS NULL;
    SQL
  end
end
