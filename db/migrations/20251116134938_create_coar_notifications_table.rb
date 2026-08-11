# COAR Notify Database Schema
# W3C LDN + COAR Notify Specification Compliant
#
# This migration creates the coar_notifications table for storing
# both sent (outbox) and received (inbox) COAR Notify notifications
# in compliance with the W3C Linked Data Notifications specification.
# See: https://coar-notify.net/specification/

Sequel.migration do
  change do
    create_table(:coar_notifications) do
      primary_key :id

      String :notification_id, null: false
      String :direction, null: false
      column :notification_types, 'text[]', null: false
      String :origin_id, null: false
      String :origin_inbox
      String :target_id, null: false
      String :target_inbox
      Text :object_id, null: false
      String :object_type
      Text :context_id
      String :context_type
      String :in_reply_to
      String :actor_id
      String :actor_name
      Text :summary
      column :payload, :jsonb, null: false
      String :paper_doi
      Integer :issue_id
      String :service_name
      String :status, null: false, default: 'pending'
      # 'pending', 'processing', 'processed', 'failed'
      Text :error_message
      # Error details if processing failed
      DateTime :processed_at
      # When processing completed
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      # Composite unique constraint mostly for testing purposes 
      # where we outbox a notification to our own inbox.
      index [:notification_id, :direction], unique: true
      index :notification_id  
      index :direction
      index :origin_id
      index :target_id
      index :object_id
      index :context_id
      index :in_reply_to
      index :paper_doi
      index :issue_id
      index :service_name
      index :status
      index [:direction, :status]
      index [:paper_doi, :direction]
      index [:service_name, :direction]
      index :notification_types, type: 'gin'  # GIN index for array queries
      index :payload, type: 'gin'              # GIN index for JSONB queries
    end
  end
end