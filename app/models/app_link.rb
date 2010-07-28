class AppLink < ActiveRecord::Base

  belongs_to :user
  validates_uniqueness_of :app_user_id, :scope => :provider
  validates_uniqueness_of :user_id, :scope => :provider, :allow_nil => true

  def self.providers
    Array(APP_CONFIG['oauth_providers']).collect { |key,provider| {:type => :oauth, :name => provider['name'] }}  +
    Array(APP_CONFIG['openid_providers']).collect { |key,provider|  {:type => :openid, :name => provider['name'] }}
  end

end
