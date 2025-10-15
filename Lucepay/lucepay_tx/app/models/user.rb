class User < ApplicationRecord
  # Associations
  has_one :wallet

  # Validations
  validates :name, presence: true
  validates :email, presence: true, uniqueness: true

  # Callbacks
  after_create :create_wallet
end