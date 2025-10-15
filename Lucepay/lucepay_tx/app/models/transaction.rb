class Transaction < ApplicationRecord
  # Associations
  belongs_to :wallet_from, class_name: 'Wallet'
  belongs_to :wallet_to, class_name: 'Wallet'
  has_many :ledger_entries

  # Validations
  validates :amount_cents, presence: true, numericality: { greater_than: 0 }
  validates :status, presence: true
  validates :client_token, presence: true, uniqueness: true

  # Enums (placeholders for future implementation)
  # enum status: { pending: 'pending', completed: 'completed', failed: 'failed' }
end