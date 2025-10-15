class LedgerEntry < ApplicationRecord
  # Associations
  belongs_to :transaction
  belongs_to :wallet

  # Validations
  validates :change_cents, presence: true, numericality: true
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :entry_type, presence: true

  # Enums for entry types
  enum entry_type: { credit: 'credit', debit: 'debit' }

  # Scopes for easier querying
  scope :credits, -> { where(entry_type: :credit) }
  scope :debits, -> { where(entry_type: :debit) }
  scope :for_wallet, ->(wallet_id) { where(wallet_id: wallet_id) }
  scope :ordered_by_date, -> { order(created_at: :asc) }
end