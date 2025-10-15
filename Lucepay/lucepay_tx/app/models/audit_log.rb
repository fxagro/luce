class AuditLog < ApplicationRecord
  # Validations
  validates :auditable_type, presence: true
  validates :auditable_id, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :action, presence: true
  validates :data, presence: true

  # Enums (placeholders for future implementation)
  # enum action: { create: 'create', update: 'update', delete: 'delete' }
end